/* TODO: add args and kwargs in separate columns */ 
ALTER TABLE que_jobs
  ADD COLUMN kwargs jsonb default '{}';
