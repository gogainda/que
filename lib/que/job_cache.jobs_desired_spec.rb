# frozen_string_literal: true

require 'spec_helper'

describe Que::JobCache, "jobs_desired" do
  class DummyWorker
    attr_reader :thread

    def initialize(priority:, job_cache:)
      @thread = Thread.new do
        job_cache.shift(priority)
      end
    end

    def kill
      @thread.kill
    end
  end

  let :worker_priorities do
    [10, 10, 30, 30, 50, 50, nil, nil, nil, nil]
  end

  let(:maximum_size) { 8 }
  let(:minimum_size) { 2 }

  let :job_cache do
    Que::JobCache.new(
      maximum_size: maximum_size,
      minimum_size: minimum_size,
      priorities: worker_priorities.uniq,
    )
  end

  let :dummy_workers do
    worker_priorities.shuffle.map do |priority|
      DummyWorker.new(
        priority: priority,
        job_cache: job_cache,
      )
    end
  end

  def fill_cache(amounts)
    metajobs = []

    amounts.each do |priority, count|
      count.times do
        metajobs << new_metajob(priority: priority)
      end
    end

    job_cache.push(*metajobs)
  end

  def assert_desired(expected)
    actual = nil
    sleep_until!(0.5) do
      actual = job_cache.jobs_desired
      actual == expected
    end
  rescue
    assert_equal expected, actual # Better error message.
  end

  def new_metajob(key)
    key[:queue]  ||= ''
    key[:run_at] ||= Time.now
    key[:id]     ||= rand(1_000_000_000)
    Que::Metajob.new(key)
  end

  before do
    sleep_until { dummy_workers.all? { |w| w.thread.status == 'sleep' } }
  end

  after { dummy_workers.each(&:kill) }

  describe "when the job queue is empty and there are unprioritized workers" do
    it "should ask for enough jobs to satisfy all of its unprioritized workers and fill the queue" do
      assert_desired [12, 32767]
    end
  end

  describe "when the unprioritized workers are all busy" do
    before { fill_cache(100 => 4) }

    it "should only ask for jobs to fill the cache" do
      assert_desired [8, 32767]
    end
  end

  describe "when the cache is full and the unprioritized workers are busy" do
    before { fill_cache(100 => 12) }

    it "should only ask for jobs at the next priority level" do
      assert_desired [2, 50]
    end
  end

  describe "when the job queue is completely full" do
    before { fill_cache(5 => 18) }

    it "should ask for zero jobs" do
      assert_desired [0, 32767]
    end
  end

  describe "when the maximum cache size is zero" do
    let(:maximum_size) { 0 }
    let(:minimum_size) { 0 }

    describe "and all the workers are free" do
      it "should only ask for jobs at the next priority level" do
        assert_desired [4, 32767]
      end
    end

    describe "and the unprioritized workers are busy" do
      before { fill_cache(100 => 4) }

      it "should only ask for jobs at the next priority level" do
        assert_desired [2, 50]
      end
    end

    describe "and all the workers are busy" do
      before { fill_cache(5 => 10) }

      it "should ask for zero jobs" do
        assert_desired [0, 32767]
      end
    end
  end
end