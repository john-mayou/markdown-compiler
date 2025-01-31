task :default => :test

task :test do
  Dir.glob('./*.rb').each { require it }
  Dir.glob('./*_test.rb').each { require it }
end