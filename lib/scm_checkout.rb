require 'open-uri'
require 'open3'
require 'json'

class InvalidSchemeError < RuntimeError; end

class ScmCheckout
  attr_accessor :name, :url, :options, :app, :commit
  
  def initialize(app, url, commit = nil)
    self.options = app.options
    self.app = app
    self.url = url
    self.commit = commit
  end
  
  def name=(name)
    @name = name.gsub(/[^a-z0-9\-\/]/i, '_')
  end
  
  def register_project
    puts "#{Time.now}: Registering project #{name}"
    ready_project
    app.recent_store.push(options.scm_adapter.libraries[name])
    puts "#{Time.now}: Adding #{name} to recent projects list"
  end
  
  def remove_project
  end
  
  def ready_project
    cmd = "touch #{repository_path}/.yardoc/complete"
    sh(cmd, "Readying project #{name}", false)
    unlink_error_file
  end
  
  def unready_project
    cmd = "rm #{repository_path}/.yardoc/complete"
    sh(cmd, "Unreadying project #{name}", false)
  end
  
  def repository_path
    File.join(options.repos, name, commit)
  end
  
  def flush_cache
    files = ["github.html", "github/#{project[0,1]}.html", 
      "github/#{name}.html", "github/#{name}", "list/github/#{name}", 
      "index.html", ".html"]
    rm_cmd = "rm -rf #{files.map {|f| File.join(options.public, f) }.join(' ')}"
    sh(rm_cmd, "Flushing cache for #{name}", false)
  end
  
  def checkout
    unlink_error_file
    unready_project
    success = sh(checkout_command, "Checking out #{name}") == 0
    if success
      register_project 
    else
      remove_project
    end
    success
  end
  
  def checkout_command
    raise NotImplementedError
  end
  
  def error_file
    @error_file ||= 
      "#{options.tmp}/#{[name.gsub('/', '_'), commit || 'master'].join('_')}.error.txt"
  end
  
  def write_error_file(out)
    File.open(error_file, "a") {|f| f.write(out + "\n") }
  end
  
  def unlink_error_file
    File.unlink(error_file) if File.file?(error_file)
  end
  
  def sh(command, title = "", write_error = true)
    puts(log = "#{Time.now}: #{title}: #{command}")
    if write_error
      result, out_data, err_data = 0, "", ""
      Open3.popen3(command) do |_, out, err, thr|
         out_data, err_data, result = out.read, err.read, thr.value
      end
    else
      `#{command}`
      result = $?
    end
    puts(log = "#{Time.now}: #{title}, result=#{result.to_i}")
    if write_error && result != 0
      data = "#{log}\n\nSTDOUT:\n#{out_data}\n\nSTDERR:\n#{err_data}\n\n"
      write_error_file(data)
    end
    result
  end
end

class GithubCheckout < ScmCheckout
  attr_accessor :username, :project
  
  def initialize(app, url, commit = nil)
    super
    case url
    when Array
      self.username, self.project = *url
    when %r{^(?:https?|git)://(?:www\.?)?github\.com/([^/]+)/([^/]+?)(?:\.git)?/?$}
      self.username, self.project = $1, $2
    else
      raise InvalidSchemeError
    end
    self.name = "#{username}/#{project}"
  end
  
  def commit=(value)
    value = nil if value == ''
    @commit = value || 'master'
    @commit = @commit[0,6] if @commit.length == 40
    @commit
  end
  
  def repository_path
    File.join(options.repos, project, username, commit)
  end
  
  def remove_project
    cmd = "rmdir #{options.repos}/#{project}/#{username} #{options.repos}/#{project}"
    sh(cmd, "Removing #{name}", false)
  end

  def checkout_command
    "#{git_checkout_command} && yardoc -n -q"
  end
  
  def fork?
    return @is_fork unless @is_fork.nil?
    if !File.directory?(File.join(options.repos, name))
      json = JSON.parse(open("http://github.com/api/v1/json/#{username}").read)
      proj_json = json["user"]["repositories"].find {|s| s["name"] == project }
      @is_fork = proj_json["fork"] if proj_json
    else
      @is_fork = true
    end
    @is_fork
  rescue IOError, OpenURI::HTTPError, Timeout::Error
    @is_fork = false
  ensure
  end
  
  private

  def git_checkout_command
    if File.directory?(repository_path)
      "cd #{repository_path} && git reset --hard && git pull --force"
    else
      fork_cmd = fork? ? nil : "echo #{project}/#{username} > ../../.master_fork"
      checkout = if commit
        "git fetch && trap \"git pull origin #{commit}\" TERM && git checkout #{commit}"
      else
        nil
      end
      ["mkdir -p #{options.repos}/#{project}/#{username}", 
        "cd #{options.repos}/#{project}/#{username}", 
        "git clone #{url} #{commit}", "cd #{commit}",
        checkout, fork_cmd].compact.join(" && ")
    end
  end
end
