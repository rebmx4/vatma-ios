require 'fileutils'
require 'xcodeproj'
require 'json'

source, smoke_source, config_path = ARGV
config = JSON.parse(File.read(config_path))
app_dir = File.join(source, 'ios/brave-ios/App')
project_path = File.join(app_dir, 'Client.xcodeproj')
project = Xcodeproj::Project.open(project_path)
client = project.targets.find { |target| target.uuid == 'F84B21BD1A090F8100AAB793' }
raise 'Native browser target not found' unless client

test_dir = File.join(app_dir, 'ATMASmokeTests')
FileUtils.mkdir_p(test_dir)
FileUtils.cp(smoke_source, File.join(test_dir, 'ATMASmokeTests.swift'))
ui = project.new_target(:ui_test_bundle, 'ATMASmokeTests', :ios, '18.0')
group = project.main_group.new_group('ATMASmokeTests', 'ATMASmokeTests')
ui.add_file_references([group.new_file('ATMASmokeTests.swift')])
ui.add_dependency(client)
ui.build_configurations.each do |configuration|
  configuration.build_settings['SWIFT_VERSION'] = '6.0'
  configuration.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = config.fetch('bundle_id') + '.uitests'
  configuration.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  configuration.build_settings['TEST_TARGET_NAME'] = 'Client'
  configuration.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
end
project.save

schemes = File.join(project_path, 'xcshareddata/xcschemes')
scheme = Xcodeproj::XCScheme.new(File.join(schemes, 'Release.xcscheme'))
scheme.add_test_target(ui)
scheme.test_action.build_configuration = 'Release'
scheme.save_as(project_path, 'ATMA', true)
