#
# Notes:
#  * Sorts the Step versions in Descending order
#  * Adds a 'latest' item to every Step, which is the same as the first version
#

require 'find'
require "safe_yaml/load"
require 'optparse'
require 'json'


options = {
  output_file_path: nil,
  steplib_info_file: "../steplib.yml",
  step_collection_folder: "../steps"
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

unless options[:output_file_path]
  puts "[!] Output JSON File Path is missing"
  puts opt_parser
  exit 1
end

puts "--- Config:"
puts options
puts "-----------"

# --- UTILS ---

def whitelist_hash(inhash, whitelist)
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

def json_step_item_from_yaml_hash(yaml_hash)
  whitelisted = whitelist_hash(yaml_hash, [
    'name', 'description', 'website',
    'host_os_tags', 'type_tags', 'requires_admin_user'
    ])
  whitelisted['source'] = whitelist_hash(yaml_hash['source'], ['git'])
  if yaml_hash['inputs']
    whitelisted['inputs'] = yaml_hash['inputs'].map {|itm|
      itm['is_expand'] = true if itm['is_expand'].nil?
      whitelist_hash(itm, ['title', 'mapped_to', 'is_expand'])
    }
  else
    whitelisted['inputs'] = []
  end

  if yaml_hash['outputs']
    whitelisted['outputs'] = yaml_hash['outputs'].map {|itm| whitelist_hash(itm, ['title', 'mapped_to'])}
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

steps_and_versions = {}
Find.find(options[:step_collection_folder]) do |path|
  if FileTest.directory?(path)
    next
  else
    if match = path.match(/steps\/([a-zA-z0-9-]*)\/([0-9]*\.[0-9]*\.[0-9]*)\/step.yml\z/)
      stepid, stepver = match.captures
      step_version_item = json_step_item_from_yaml_hash(SafeYAML.load_file(path))

      unless steps_and_versions[stepid]
        steps_and_versions[stepid] = default_step_data_for_stepid(stepid)
      end

      step_version_item['version_tag'] = stepver
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
