task :default => :test

task :test do
  if method = ENV['TEST']
    Dir.glob('./*_test.rb').each { system("ruby #{it} --name #{method}") }
  else
    Dir.glob('./*_test.rb').each { require it }
  end
end