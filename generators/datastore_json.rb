#
# Notes:
#  * Sorts the Step versions in Descending order
#  * Adds a 'latest' item to every Step, which is the same as the first version
#

require 'find'
require "safe_yaml/load"
require 'optparse'
require 'json'
require 'steplib'

# --- StepLib Collection specific options
DEFAULT_step_assets_url_root = 'https://github.com/bitrise-io/bitrise-step-collection/tree/master/steps'
DEFAULT_steplib_source = 'https://github.com/bitrise-io/bitrise-step-collection'
# ---


def env_or_default(env_key, default_value)
  env_val = ENV[env_key]
  if env_val
    return env_val 
  end
  return default_value
end

options = {
  output_file_path: nil,
  steplib_info_file: env_or_default('STEPLIB_INFO_FILE_PATH', '../steplib.yml'),
  step_collection_folder: env_or_default('STEPS_FOLDER_PATH', '../steps'),
  step_assets_url_root: env_or_default('STEP_ASSETS_URL_ROOT', DEFAULT_step_assets_url_root),
  steplib_source: env_or_default('STEPLIB_SOURCE', DEFAULT_steplib_source),
  is_pretty_json: false
}
opt_parser = OptionParser.new do |opt|
  opt.banner = "Usage: generate_steplib_json.rb [OPTIONS]"
  opt.separator  ""
  opt.separator  "Options"

  opt.on("-o", "--outputfile OUTPUT_FILE_PATH", "Output JSON file path") do |value|
    options[:output_file_path] = value
  end

  opt.on("-d", "--stepdir STEPS_DIR", "Steps folder path (default is #{options[:step_collection_folder]})") do |value|
    options[:step_collection_folder] = value
  end

  opt.on("-p", "--pretty", "Pretty JSON generation") do |value|
    options[:is_pretty_json] = true
  end

  opt.on("-h","--help","help") do
    puts opt_parser
    exit
  end
end
opt_parser.parse!

def check_required_options!(opts_to_check)
  is_fail = false
  opts_to_check.each do |opt_key, opt_value|
    if opt_value.nil?
      puts "[!] Required input missing: #{opt_key}"
      is_fail = true
    end
  end

  if is_fail
    yield
  end
end

check_required_options!(options) do
  puts
  puts opt_parser
  exit 1
end

puts "--- Config:"
puts options
puts "-----------"

# --- UTILS ---

def json_step_item_from_yaml_hash(yaml_hash)
  # set default values for optional properties
  yaml_hash = Steplib::SteplibUpdater.set_defaults_for_missing_properties_in_step_version(yaml_hash)
  # whitelist
  yaml_hash = Steplib::SteplibValidator.whitelist_step_version(yaml_hash)
  # validate
  Steplib::SteplibValidator.validate_step_version!(yaml_hash)

  return yaml_hash
end

def default_step_data_for_stepid(stepid)
  return  {
    'id' => stepid,
    'versions' => []
  }
end

# --- MAIN ---

steplib_data = {
  'format_version' => nil,
  'generated_at_timestamp' => nil,
  'steps' => {}
}

steplib_info = SafeYAML.load_file(options[:steplib_info_file])
steplib_data['format_version'] = steplib_info["format_version"]
steplib_data['generated_at_timestamp'] = Time.now.getutc.to_i
steplib_data['steplib_source'] = options[:steplib_source]

steps_and_versions = {}
Find.find(options[:step_collection_folder]) do |path|
  if FileTest.directory?(path)
    next
  else
    if match = path.match(/steps\/([a-zA-z0-9-]*)\/([0-9]*\.[0-9]*\.[0-9]*)\/step.yml\z/)
      stepid, stepver = match.captures
      raise 'Cant determine StepID' if stepid.nil?
      raise 'Cant determine Step Version' if stepver.nil?

      # load
      step_version_item = SafeYAML.load_file(path)
      # add IDs
      step_version_item['steplib_source'] = options[:steplib_source]
      step_version_item['version_tag'] = stepver
      step_version_item['id'] = stepid
      step_icon_file_path_256 = File.join(options[:step_collection_folder], stepid, 'assets', 'icon_256.png')
      if File.exist?(step_icon_file_path_256)
        step_version_item['icon_url_256'] = "#{options[:step_assets_url_root]}/#{stepid}/assets/icon_256.png"
      end
      # validate and whitelist
      step_version_item = json_step_item_from_yaml_hash(step_version_item)

      unless steps_and_versions[stepid]
        steps_and_versions[stepid] = default_step_data_for_stepid(stepid)
      end

      steps_and_versions[stepid]['versions'] << step_version_item
    end
  end
end

# sort and prepare structure
steps_and_versions.each do |key, value|
  stepid = key
  stepdata = value
  sorted_versions = []
  # puts "stepdata[:versions]: #{stepdata[:versions]}"
  sorted_versions = stepdata['versions'].sort do |a, b|
    a_source_tag_ver = Gem::Version.new(a['version_tag'])
    b_source_tag_ver = Gem::Version.new(b['version_tag'])
    case
    when a_source_tag_ver < b_source_tag_ver
      1
    when a_source_tag_ver > b_source_tag_ver
      -1
    else
      raise "Invalid version: found identical version tags in different versions!"
    end
  end

  stepdata['versions'] = sorted_versions
  stepdata['latest'] = sorted_versions.first
  steplib_data['steps'][stepid] = stepdata
end

# validate the generated data's format
Steplib::SteplibValidator.validate_steplib!(steplib_data)

serialized_json_str = ""
if options[:is_pretty_json]
  serialized_json_str = JSON.pretty_generate(steplib_data)
else
  serialized_json_str = JSON.generate(steplib_data)
end
puts " (i) serialized_json_str JSON: #{serialized_json_str}"

# write to file
File.open(options[:output_file_path], "w") do |f|
  f.write(serialized_json_str)
end
