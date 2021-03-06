require 'fileutils'
require 'open-uri'
require 'rubygems/package'

module YARD
  module Server
    class LibraryVersion
      protected

      def load_yardoc_from_remote_gem
        yfile = File.join(source_path, '.yardoc')
        if File.directory?(yfile)
          if File.exist?(File.join(yfile, 'complete'))
            self.yardoc_file = yfile 
            return
          else
            raise LibraryNotPreparedError 
          end
        end

        # Remote gemfile from rubygems.org
        url = "http://rubygems.org/downloads/#{to_s(false)}.gem"
        log.debug "Searching for remote gem file #{url}"
        Thread.new do
          begin
            open(url) do |io| 
              expand_gem(io)
              generate_yardoc
            end
            self.yardoc_file = yfile
          rescue OpenURI::HTTPError
          rescue IOError
            self.yardoc_file = yfile
          end
        end
        raise LibraryNotPreparedError
      end

      def source_path_for_remote_gem
        File.join(::REMOTE_GEMS_PATH, name[0].downcase, name, version)
      end
      
      alias load_yardoc_from_github load_yardoc_from_disk
      
      def source_path_for_github
        File.join(::REPOS_PATH, name.split('/', 2).reverse.join('/'), version)
      end

      private

      def generate_yardoc
        `cd #{source_path} && yardoc -n -q && touch .yardoc/complete`
      end

      def expand_gem(io)
        log.debug "Expanding remote gem #{to_s(false)} to #{source_path}..."
        FileUtils.mkdir_p(source_path)
        Gem::Package.open(io) do |pkg|
          pkg.each do |entry|
            pkg.extract_entry(source_path, entry)
          end
        end
      end
    end
  end
  
  module CLI
    class Yardoc
      def yardopts
        list = IO.read(options_file).shell_split
        list.map {|a| %w(-e --load -c --use-cache --db -b --query -r --readme).include?(a) ? '-o' : a }
      rescue Errno::ENOENT
        []
      end

      def support_rdoc_document_file!
        IO.read(File.join(File.dirname(options_file), '.document')).gsub(/^[ \t]*#.+/m, '').split(/\s+/)
      rescue Errno::ENOENT
        []
      end

      def add_extra_files(*files)
        files.map! {|f| f.include?("*") ? Dir.glob(File.join(File.dirname(options_file), f)) : f }.flatten!
        files.each do |file|
          file = File.join(File.dirname(options_file), file) unless file[0] == '/'
          if File.file?(file)
            options[:files] << file.gsub(File.dirname(options_file) + '/', '')
          end
        end
      end
    end
  end
end
