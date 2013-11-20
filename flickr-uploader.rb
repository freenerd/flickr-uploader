#
# This script handles the command line input only
# The actual logic is in /lib
#

require_relative 'lib/flickr-uploader.rb'
require 'optparse'

options = {}
options_parser =
  OptionParser.new do |opts|
    opts.banner = "Usage: flickr-uploader.rb [options]"

    opts.on("-c", "--connect", "Interactive mode to connect your Flickr account") do
      options[:connect] = true
    end

    opts.on("-u", "--upload DIRECTORY", "Directory of the files to be uploaded to Flickr") do |directory|
      options[:upload] = true
      options[:directory] = directory
    end

    opts.on("-p", "--public", "If set, uploaded items will be public. Otherwise everything will be made private") do
      options[:public] = true
    end

    opts.on("-n", "--photoset-name NAME", "Creates a photoset with the given name and adds all uploaded items to it") do |name|
      options[:photoset_name] = name
    end

    opts.on("--photoset-id ID", "Adds all uploaded items to the photoset with the ID") do |id|
      options[:photoset_id] = id
    end

    opts.on("-d", "--dry", "Don't do the action, but only act as if and show the according output") do
      options[:dry] = true
    end

    opts.on("--list-photosets", "List all the photosets") do
      options[:list_photosets] = true
    end

    opts.on("--delete-photoset PHOTOSET_ID", "This deletes all photos in a photoset") do |photoset_id|
      options[:delete_photoset] = photoset_id
    end

    opts.on_tail("-h", "--help", "Show this message") do
      puts opts
      exit
    end
  end
options_parser.parse!

if(options[:connect])
  FlickrUpload::Config.new.connect
elsif(options[:upload])
  FlickrUpload.new(options).upload
elsif(options[:list_photosets])
  FlickrUpload.new(options).list_photosets
elsif(options[:delete_photoset])
  FlickrUpload.new(options).delete_photoset(options[:delete_photoset])
else
  puts options_parser
end
