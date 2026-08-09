# Sized for a Heroku Basic dyno (512 MB RAM). Raising WEB_CONCURRENCY without
# raising the dyno size will produce R14/R15 memory errors.
workers Integer(ENV.fetch('WEB_CONCURRENCY', 2))

threads_count = Integer(ENV.fetch('MAX_THREADS', 5))
threads threads_count, threads_count

preload_app!

port        ENV.fetch('PORT', 3000)
environment ENV.fetch('RACK_ENV', 'development')
