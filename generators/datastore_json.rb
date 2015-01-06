#
# Notes:
#  * Sorts the Step versions in Descending order
#  * Adds a 'latest' item to every Step, which is the same as the first version
#

require 'find'
require "safe_yaml/load"
require 'optparse'
require 'json'

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
  steplib_source: env_or_default('STEPLIB_SOURCE', DEFAULT_steplib_source)
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

#
# All the input whitelist keys have to be defined
# and the returned hash will only contain the
#  whitelisted key-value pairs.
def whitelist_require_hash(inhash, whitelist)
  raise "Input hash is nil" if inhash.nil?

  res_hash = {}
  whitelist.each do |whiteitm|
    if inhash[whiteitm].nil?
      raise "Missing whitelisted item: #{whiteitm} | in hash: #{inhash}"
    end
    res_hash[whiteitm] = inhash[whiteitm]
  end
  return res_hash
end

#
# Sets the provided default value for the specified
#  key if the key is missing.
# Defaults_arr is an array of {:key=>,:value=>} hashes
def set_missing_defaults(inhash, defaults_arr)
  defaults_arr.each do |a_def|
    a_def_key = a_def[:key]
    a_def_value = a_def[:value]
    if inhash[a_def_key].nil?
      inhash[a_def_key] = a_def_value
    end
  end
  return inhash
end

def json_step_item_from_yaml_hash(yaml_hash)
  # set default values for optional properties
  whitelisted = set_missing_defaults(yaml_hash, [
    {key: 'fork_url', value: yaml_hash['website']},
    {key: 'project_type_tags', value: []}
    ])
  # 
  whitelisted = whitelist_require_hash(whitelisted, [
    'name', 'description',
    'website', 'fork_url',
    'host_os_tags', 'project_type_tags', 'type_tags',
    'is_requires_admin_user'
    ])
  #
  whitelisted['source'] = whitelist_require_hash(yaml_hash['source'], ['git'])
  if yaml_hash['inputs']
    whitelisted['inputs'] = yaml_hash['inputs'].map {|itm|
      whitelisted_itm = set_missing_defaults(itm, [
        {key: 'is_expand', value: true},
        {key: 'description', value: ''},
        {key: 'is_required', value: false},
        {key: 'value_options', value: []},
        {key: 'value', value: ''},
        {key: 'is_dont_change_value', value: false}
        ])
      whitelisted_itm = whitelist_require_hash(whitelisted_itm,
        ['title', 'description', 'mapped_to', 'is_expand',
          'is_required', 'value_options', 'value', 'is_dont_change_value'])
      # force / convert type
      whitelisted_itm['value_options'] = whitelisted_itm['value_options'].map { |e| e.to_s }
      whitelisted_itm['value'] = whitelisted_itm['value'].to_s
      # return:
      whitelisted_itm
    }
  else
    whitelisted['inputs'] = []
  end

  if yaml_hash['outputs']
    whitelisted['outputs'] = yaml_hash['outputs'].map { |itm|
      whitelisted_itm = set_missing_defaults(itm, [
        {key: 'description', value: ''}
        ])
      # return:
      whitelist_require_hash(itm, ['title', 'description', 'mapped_to'])
    }
  else
    whitelisted['outputs'] = []
  end

  return whitelisted
end

def default_step_data_for_stepid(stepid)
  return  {
    id: stepid,
    versions: []
  }
end

# --- MAIN ---

steplib_data = {
  format_version: nil,
  generated_at_timestamp: nil,
  steps: {}
}

steplib_info = SafeYAML.load_file(options[:steplib_info_file])
steplib_data[:format_version] = steplib_info["format_version"]
steplib_data[:generated_at_timestamp] = Time.now.getutc.to_i
steplib_data[:steplib_source] = options[:steplib_source]

steps_and_versions = {}
Find.find(options[:step_collection_folder]) do |path|
  if FileTest.directory?(path)
    next
  else
    if match = path.match(/steps\/([a-zA-z0-9-]*)\/([0-9]*\.[0-9]*\.[0-9]*)\/step.yml\z/)
      stepid, stepver = match.captures
      raise 'Cant determine StepID' if stepid.nil?
      raise 'Cant determine Step Version' if stepver.nil?
      step_version_item = json_step_item_from_yaml_hash(SafeYAML.load_file(path))

      unless steps_and_versions[stepid]
        steps_and_versions[stepid] = default_step_data_for_stepid(stepid)
      end

      step_version_item['steplib_source'] = options[:steplib_source]
      step_version_item['version_tag'] = stepver
      step_version_item['id'] = stepid
      step_icon_file_path_256 = File.join(options[:step_collection_folder], stepid, 'assets', 'icon_256.png')
      if File.exist?(step_icon_file_path_256)
        step_version_item['icon_url_256'] = "#{options[:step_assets_url_root]}/#{stepid}/assets/icon_256.png"
      end
      steps_and_versions[stepid][:versions] << step_version_item
    end
  end
end

# sort and prepare structure
steps_and_versions.each do |key, value|
  stepid = key
  stepdata = value
  sorted_versions = []
  # puts "stepdata[:versions]: #{stepdata[:versions]}"
  sorted_versions = stepdata[:versions].sort do |a, b|
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

  stepdata[:versions] = sorted_versions
  stepdata[:latest] = sorted_versions.first
  steplib_data[:steps][stepid] = stepdata
end

# Gem::Version.new('0.4')

puts " steplib_data: #{steplib_data.to_json}"

# write to file
File.open(options[:output_file_path], "w") do |f|
  f.write(steplib_data.to_json)
end
