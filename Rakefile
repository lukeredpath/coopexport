require 'rake'
require 'spec/rake/spectask'

desc "Run all specs"
Spec::Rake::SpecTask.new('spec') do |t|
  t.spec_files = FileList['spec/**/*_spec.rb']
  t.spec_opts  = ['--options', 'spec/spec.opts']
end

task :default => :spec