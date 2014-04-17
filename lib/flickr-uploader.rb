require 'yaml'

require 'flickraw'

FlickRaw.api_key="15f8ac054e62ed2373cfbd9097730ce3"
FlickRaw.shared_secret="404cbccb61ecb16a"

class FlickrUpload
  class Config
    CONFIG_FILENAME = "config.yml"

    def initialize
      if File.exists?(CONFIG_FILENAME)
        file = File.open(CONFIG_FILENAME, "r")
        @config = YAML.load(file.read)

        unless @config && @config[:access_token] && @config[:access_token_secret]
          raise "Problem with config.yml. Please delete the file and try to connect again."
        end

        file.close
      else
        @config = {
          :access_token => nil,
          :access_token_secret => nil,
        }
      end
    end

    def connect
      if load_config && username = get_username
        puts "You already have the Flickr account '#{username}' connected."
        puts "Do you want to connect a new account? [y/n]"
        input = gets.chomp

        return if input.match(/n/i)
      end

      authenticate
    end

    def load_config
      return false unless @config[:access_token] && @config[:access_token_secret]

      flickr.access_token = @config[:access_token]
      flickr.access_secret = @config[:access_token_secret]

      self
    end

    def get_username
      begin
        return flickr.test.login.username
      rescue FlickRaw::OAuthClient::FailedResponse
        return false
      end
    end

    private

    def authenticate
      puts "Authenticating with Flickr ..."
      token = flickr.get_request_token
      auth_url = flickr.get_authorize_url(token['oauth_token'], :perms => 'delete')

      puts "Open the following url in your browser and approve the application"
      puts auth_url
      puts "Then copy here the number given in the browser and press enter:"
      verify = gets.strip

      begin
        flickr.get_access_token(token['oauth_token'], token['oauth_token_secret'], verify)
        login = flickr.test.login
        puts "You are now authenticated as #{login.username} with token #{flickr.access_token} and secret #{flickr.access_secret}"
      rescue FlickRaw::FailedResponse => e
        puts "Authentication failed : #{e.msg}"
        return
      end

      @config[:access_token] = flickr.access_token
      @config[:access_token_secret] = flickr.access_secret

      write_config
    end

    def write_config
      file = File.open(CONFIG_FILENAME, "w")
      file.puts(YAML.dump(@config))
      file.close
    end
  end
end

class FlickrUpload
  class Log
    LOG_FILENAME = "log.yml"

    def initialize(directory, dry=false)
      @dry = dry
      @directory = directory

      new_log = { :runs => [], :photos => [], :photoset => {} }

      if File.exists?(LOG_FILENAME)
        file = File.open(LOG_FILENAME, "r")
        @log_file = YAML.load(file.read)
        file.close
      else
        @log_file = {
          directory => new_log
        }
      end

      @log = @log_file[directory] || new_log
      @log[:runs] << Time.now.to_s
    end

    def photoset
      @log[:photoset] || {}
    end

    def photoset=(dict)
      @log[:photoset] = dict
    end

    def add_photo(photo_id, filename)
      @log[:photos] << { :photo_id => photo_id, :filename => filename }
    end

    def already_uploaded?(photo_id)
      @log[:photos].map { |p| p[:filename] }.include?(photo_id)
    end

    def write
      unless @dry
        File.open(LOG_FILENAME, "w") do |file|
          @log_file[@directory] = @log
          file.puts(YAML.dump(@log_file))
        end
      end
    end
  end
end

class FlickrUpload
  def initialize(options)
    @config = Config.new
    @config.load_config
    @config.connect unless @config.get_username

    @options = options
    puts "Dry Run" if @options[:dry]
  end

  def upload
    initialize_log
    initialize_photoset
    upload_directory(@options[:directory])
  end

  def list_photosets
    flickr.photosets.getList(:per_page => 500).each do |photoset|
      puts "#{photoset.id} #{photoset.title} (#{photoset.photos} photos/ #{photoset.videos} videos)"
    end
  end

  def delete_photoset(photoset_id)
    begin
      photoset = flickr.photosets.getInfo(:photoset_id => photoset_id)
    rescue FlickRaw::FailedResponse
      puts "The photoset with the ID #{photoset_id} does not exist."
      puts "You can see all your photosets by using the --list-photosets option"
      return
    end

    puts "You are about to delete photoset #{photoset.id} #{photoset.title} with #{photoset.count_photos} photos and #{photoset.count_videos} videos"
    puts "Are you sure, you want to delete that photoset including all photos and videos? [y/n]"
    input = gets.chomp
    return if input.match(/n/i)

    counter = {
      :deleted => 0,
      :total => photoset.count_photos.to_i + photoset.count_videos.to_i,
    }

    loop do
      begin
        photos_object = flickr.photosets.getPhotos(
          :photoset_id => photoset_id,
          :media => 'all',
          :page => 1,
          :per_page => 500)
      rescue FlickRaw::FailedResponse
        # if a photoset has no items in it, it gets deleted as well
        # thus we get a FailedResponse and assume we are done
        break
      end

      photos_object.photo.each do |item|
        begin
          flickr.photos.delete(:photo_id => item.id) unless @options[:dry]
        rescue
          puts "Deleting failed ... trying again"
          sleep 1
          retry
        end

        counter[:deleted] += 1
        puts "[#{counter[:deleted]}/#{counter[:total]}] Deleted photo #{item.id} #{item.title}"
      end
    end

    puts "Photoset #{photoset.id} sucessfully deleted"
  end

  private

  def initialize_log
    @log = Log.new(@options[:directory], @options[:dry])
  end

  def initialize_photoset
    unless @log.photoset[:id]
      @log.photoset = {
        :id => @options[:photoset_id],
        :name => @options[:photoset_name]
      }
    end
  end

  def upload_directory(directory)
    raise "Can't find directory #{directory}" unless Dir.exists?(directory)

    files = Dir.glob(File.join(directory, "*"))
    puts "Found #{files.length} files in the directory"

    files.each_with_index do |filename, index|
      print "[#{index+1}/#{files.length}] "

      if @log.already_uploaded?(filename)
        puts "File #{filename} has already been uploaded. Skipping."
      else
        begin
          photo_id = upload_photo(filename)
          make_private    photo_id unless @options[:public]
          add_to_photoset photo_id if @log.photoset[:id] or @log.photoset[:name]
          @log.add_photo  photo_id, filename
          @log.write
        rescue => e
            puts "Failed to upload #{filename} with error #{e}"
        end
      end
    end

    puts "Finished uploading."
  end

  def upload_photo(filename)
    photo_id =
      execute do
        flickr.upload_photo(filename)
      end

    puts "Uploaded picture #{filename} to id #{photo_id}"

    photo_id
  end

  def make_private(photo_id)
    execute do
      flickr.photos.setPerms(
        :photo_id => photo_id,
        :is_public => 0,
        :is_friend => 0,
        :is_family => 0,
        :perm_comment => 3,
        :perm_addmeta => 3
      )
    end

    photo_id
  end

  def add_to_photoset(photo_id)
    execute do
      if @log.photoset[:id]
        flickr.photosets.addPhoto(
          :photoset_id => @log.photoset[:id],
          :photo_id => photo_id)
      else
        photoset = flickr.photosets.create(
          :title => @options[:photoset_name],
          :primary_photo_id => photo_id)
        @log.photoset = {
          :id => photoset["id"],
          :name => @options[:photoset]
        }
      end
    end

    puts "Added photo #{photo_id} to photoset #{@log.photoset[:id]} #{@log.photoset[:name]}"

    photo_id
  end

  def execute(&block)
    unless @options[:dry]
      begin
        return block.call
      rescue => e
        if is_retry_error(e)
          puts "Call to Flickr API failed with error #{e}. Trying again in a bit ..."
          sleep 2
          retry
        else
          raise e
        end
      end
    end
  end

  def is_retry_error(e)
    [      # codes according to https://secure.flickr.com/services/api/upload.api.html
      3,   # general upload error
      105, # Service currently unavailable
      106  # Write operation failed
    ].include?(e.code)
  end

  def get_most_recent
    flickr.photos.recentlyUpdated(:min_date => Time.now.to_i - 60 * 60 * 24, :per_page => 20)
  end

  def delete_photo(photo_id)
    flickr.photos.delete(:photo_id => photo_id)
  end
end
