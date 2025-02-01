task :default => :test

task :test do
  env = ''
  env << 'UPDATE=true' if ENV['UPDATE']

  arg = ''
  arg << " --name #{ENV['TEST']}" if ENV['TEST']

  files = Dir.glob('./*_test.rb').join(' ')

  system("#{env} ruby #{files} #{arg}")
end