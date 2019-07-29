# -*- coding: utf-8 -*-

VERSION = "0.1.0"
SPLIT_LINE = '-'*21 + 10.chr

FailedImage   = Struct.new(:page_url, :id, :folder, :hd)
FailedGallery = Struct.new(:gid, :token, :folder)
DownloadFolder = "Downloads/"

$mutex = Mutex.new
$existed_keys

# fix windows getrlimit not implement bug
if Gem.win_platform?
  module Process
    RLIMIT_NOFILE = 7
    def self.getrlimit(*args); [1024]; end
  end
end

require 'mechanize'
require 'open-uri'
require 'json'
require 'io/console'
require 'net/http'

def warning(*args)
  return if $no_warning
  args.unshift("[Warning]:").push(SPLIT_LINE)
  puts(*args)
end

# Continue program or exit
def request_continue(msg='', **kwargs)
  print("#{msg}\nContinue?(Y/N): ") unless msg.nil?
  _ch = ''
  _ch = STDIN.getch.upcase until _ch == 'Y' || _ch == 'N'
  puts _ch
  if _ch == 'N'
    return exit() unless kwargs[:no]
    kwargs[:no].call()
  elsif kwargs[:yes]
    kwargs[:yes].call()
  end
end

alias exit_res exit
def exit(*args)
  puts("Press any key to exit...")
  STDIN.getch
  exit_res(*args)
end

# Request gallery meta with API
def request_gallery_meta(gidlist)
  gidlist = gidlist[0...25] if gidlist.size > 25
  post_param = {
    "method" => "gdata",
    "gidlist" => gidlist,
    "namespace" => 1,
  }
  response_str = Net::HTTP.post(
    URI('https://api.e-hentai.org/api.php'), 
    post_param.to_json,  
    "Content-Type" => "application/json").body  
  return JSON.parse(response_str)['gmetadata']
end

def eval_action(load_msg='', &block)
  print(load_msg)
  begin
    yield block
  rescue Exception => err
    puts("An error occurred!")
    puts("#{err}\n#{SPLIT_LINE}")
    puts("This action will be skipped")
  end
  puts("succeed")
end

# core_ext
class Object
  def boolean?; self == true || self == false; end
end

class Integer
  def to_fileid(deg=4) # %04d
    return sprintf("%0#{deg}d", self)
  end
end

class Agent < Mechanize
  attr_reader :current_doc, :existed_json, :flag_working, :new_json
  attr_accessor :failed, :search_param
  attr_accessor :start_page, :end_page, :cur_page

  def initialize(*args)
    @current_doc = nil
    @flag_working = false
    @failed   = []
    @cur_page = 0
    @search_param = ''
    @start_page = @end_page = 0
    super
  end

  def working?; @flag_working; end
  def existed_json=(_out)
    return if @existed_json.equal?(_out)
    @existed_json = _out
  end

  def new_json=(_out)
    return if @new_json.equal?(_out)
    @new_json = _out
  end

  def fetch(*args, **kwargs, &block)
    depth = 0
    _ok   = false
    _doc  = nil
    until _ok do
      begin
        depth += 1
        if depth > 5
          puts("Failed to get #{args[0]}, skipping")
          return kwargs[:fallback].call() if kwargs[:fallback]
          return nil
        end
        puts "Getting `#{args[0]}`"
        _doc = self.get(*args, &block)
        _ok  = true
      rescue Mechanize::ResponseCodeError => err
        warning("\nReceived response code #{err.response_code}, retrying...(depth=#{depth})")
        sleep(0.3)
      rescue Exception => err
        warning("\nAn error occurred during fetch page! #{err}, retrying...(depth=#{depth})")
        sleep(0.3)
      end
    end
    return _doc
  end

  def get_page_url(page_id=0)
    "https://e-hentai.org/?page=#{page_id}#{@search_param}"
  end

  def start_scan
    @flag_working = true
    @cur_page = @start_page
    
    while @cur_page < @end_page
      next_page()
      collect_metas()
    end
    @flag_working = false
  end

  def next_page
    @current_doc = fetch(get_page_url(@cur_page))
    @cur_page += 1
  end

  def collect_metas
    re  = @current_doc.links_with(href: /https:\/\/e-hentai.org\/g\//).uniq{|l| l.href}
    re.each do |link|
      _url = link.href.split('/')
      gid, token = _url[-2].to_i, _url[-1]
      $mutex.synchronize{$download_targets << {'gid' => gid, 'token' => token}}
      if meta_exist?(gid)
        puts "#{gid}/#{token} is already existed, skipping"
        $mutex.synchronize{$existed_gal_cnt += 1}
        next
      end
      $mutex.synchronize{
        @new_json << {'gid' => gid, 'token' => token}
      }
    end
  end

  def meta_exist?(gid)
    return @existed_json.any?{|obj| obj['gid'] == gid}
  end

  def start_download(init_url, gid, token)
    @flag_working = true
    @current_doc  = fetch(init_url, fallback: Proc.new{on_fetch_failed(init_url)})
    @cur_page     = @start_page
    @cur_folder   = EHentaiDownloader.cur_folder
    @cur_gid, @cur_token = gid, token
    loop do
      break if @current_doc.nil?
      @cur_parent_url = @current_doc.uri
      dowload_current_image()
      wait4download()
      break if @end_page == @cur_page
      @cur_page += (@end_page > @start_page ? 1 : -1)
      next_link = get_next_link()
      @current_doc = fetch(next_link, fallback: Proc.new{on_fetch_failed(next_link)})
    end
    @flag_working = false
  end

  def dowload_current_image(download_hd=EHentaiDownloader.config[:download_original])
    @thread_lock = true
    @flag_download_hd = download_hd
    img_url = nil
    if download_hd
      img_url = @current_doc.links_with(href: /https:\/\/e-hentai.org\/fullimg.php/).first.href rescue nil
    end
    img_url = @current_doc.css("[@id='img']").first.attr('src') if img_url.nil?
    @worker = Thread.new{download_image_async(img_url,); @thread_lock = false;}
  end

  def on_fetch_failed(url)
    puts "Gallery fetch failed in #{url}"
    $failed_galleries << FailedGallery.new(@cur_gid, @cur_token, @cur_folder)
    return nil
  end

  def on_download_failed(parent_url)
    puts "Download failed in #{parent_url}"
    $failed_images << FailedImage.new(parent_url, @cur_page, @cur_folder, @flag_download_hd)
    return nil
  end

  def download_image_async(img_url)
    filename = "#{@cur_folder}/#{@cur_page.to_fileid}.jpg"
    if ::File.exist?(filename)
      return puts("#{filename} already exists, skip")
    end
    img = self.fetch(img_url, fallback: Proc.new{on_download_failed(@cur_parent_url)})
    unless img.is_a?(::Mechanize::Image)
      warning("Unable to get original image from #{@cur_parent_url}, please check your cookie or download limits!")
      return
    end
    img.save(filename)
  end

  def wait4download()
    start_time = Time.now
    while @thread_lock
      sleep(0.3)
      if (Time.now - start_time).to_f > 10
        puts "#{@cur_page} timeouted ( > 10 sec)"
        Thread.kill(@worker)
        $mutex.synchronize{$failed_images << FailedImage.new(@cur_parent_url, @cur_page)}
        @thread_lock = false
      end
    end
  end

  def get_next_link
    begin
      return @current_doc.links_with(href: Regexp.new("#{@cur_gid}-#{@cur_page}")).first.uri
    rescue Exception => err
      puts "#{}#{@current_doc.uri}"
      raise err
    end
  end

  def redownload_images(imgs)
    imgs.each do |info|
      @cur_parent_url = info.page_url
      @cur_page       = info.id
      @cur_folder     = info.folder
      @current_doc = fetch(@cur_parent_url, fallback: Proc.new{on_fetch_failed( @cur_parent_url)})
      dowload_current_image(info.hd)
      wait4download()
    end
  end

end

class Module
  def mattr_reader(*args)
    args.each do |var|
      define_singleton_method(var.to_sym){return class_eval("@#{var}");}
    end
  end

  def mattr_accessor(*args)
    mattr_reader(*args)
    args.each do |var|
      define_singleton_method((var.to_s + '=').to_sym){|v| return class_eval("@#{var} = #{v}");}
    end
  end

end

module EHentaiDownloader
  mattr_reader :agent_head, :agent_tail, :config, :cur_folder
  mattr_reader :existed_json, :cookies, :current_doc

  GalleryURLRegex = /https:\/\/e-hentai.org\/g\/(\d+)\/(.+)/i
  ResultJsonFilename = "_metadata.json"
  BaseURL = "https://e-hentai.org/g/"
  TotalResult_regex = /Showing (.+) result/i
  TotalImg_regex    = /Showing(.+)of (.+) images/i

  TypeBitset = {
    :misc       => 0,
    :doujinshi  => 1,
    :manga      => 2,
    :arist_cg   => 3,
    :game_cg    => 4,
    :image_set  => 5,
    :cosplay    => 6,
    :asian_porn => 7,
    :non_h      => 8,
    :western    => 9
  }
  
  module_function
  def initialize
    @agent_head = Agent.new
    @agent_tail = Agent.new
    @mutex = Mutex.new
    @failed   = []
    @config   = {
      :search_options => {
        :types => { # search types
          :misc       => true,
          :doujinshi  => true,
          :manga      => true,
          :arist_cg   => true,
          :game_cg    => true,
          :image_set  => true,
          :cosplay    => true,
          :asian_porn => true,
          :non_h      => true,
          :western    => true
        },
        
        :type_bitset  => 0,
        :filter       => '',
        :s_name       => true,
        :s_tags       => true,
        :s_deleted    => true,
        :min_star     => 0,
        :page_between => [1, 9999],
        :english_title => false,
      },

      :download_original => false,
      :meta_only         => false,
    }
    eval_action("Loading config file..."){load_config()}
    eval_action("Loading cookie..."){load_cookie()}
    @agent_head.search_param = "#{get_search_param()}#{get_advsearch_param()}"
    @agent_tail.search_param = "#{get_search_param()}#{get_advsearch_param()}"
    load_existed_json()
    @existed_json ||= []
    @agent_head.existed_json = @existed_json
    @agent_tail.existed_json = @existed_json
    Dir.mkdir(DownloadFolder) unless File.exist?(DownloadFolder)
  end

  def load_existed_json
    return unless File.exist?(ResultJsonFilename)
    eval_action("Loading exited meta infos...") do
      File.open(ResultJsonFilename, 'r') do |file|
        @existed_json = JSON.load(file)
      end
    end
  end

  def search_options(sym=nil)
    return @config[:search_options] if sym.nil?
    return @config[:search_options][sym]
  end

  def load_config
    unless File.exist?("./config.txt")
      warning("Search option file not found, this will cause the program to grab >>ALL<< gallery infos!")
      in_ch = ''
      while in_ch != 'N' || in_ch != 'Y'
        print("Continue? (Y/N): ")
        in_ch = STDIN.getch.upcase
        puts in_ch
      end
      exit() if in_ch == 'N'
      return
    end

    File.open("config.txt", 'r') do |file|
      begin
        _config = eval(file.read())
      rescue Exception => err
        warning("An error occurred while loading config file:", err)
        exit()
      end
      translate_config(@config, _config)
      load_type_config()
      load_filter_config()
    end # File.open
  end

  # translate 0/1 to false/true with iterable and apply
  def translate_config(parent, child)
    child.each do |k, v|
      if parent[k] && parent[k].is_a?(Hash) && v.is_a?(Hash)
        translate_config(parent[k], v)
      else
        child[k]  = (v == 0 ? false : true) if parent[k].boolean?
        parent[k] = child[k]
      end
    end
  end

  def load_type_config()
    return unless search_options[:types]
    begin
      search_options[:types].each do |k, v|
        k = k.downcase rescue nil
        next unless TypeBitset[k]
        search_options[:type_bitset] |= (1 << TypeBitset[k]) unless v
      end
    rescue Exception => err
      warning("An error occurred while loading type config: #{err}, all types will be searched")
    end  
  end

  def load_filter_config()
    filter = modify_filter(search_options(:filter))
    search_options[:filter] = filter
    p filter
  end

  def modify_filter(filter)
    re = ''
    in_str = false
    filter.lstrip.tr("\r\n", "").each_char do |ch|
      puts if ch == '"'
      in_str ^= true if ch == '"'
      if !in_str && ch == ' '
        re += '+'
      else
        re += ch
      end
    end
    if String.respond_to?(:delete_suffix)
      re.delete_suffix!('+') until re[-1] != '+'
    else
      re.chomp!('+') until re[-1] != '+'
    end
    return re
  end

  def load_cookie()
    unless File.exist?('cookie.json')
      warning("Cookie file not found, login as guest")
      return
    end
    File.open('cookie.json', 'r') do |file|
      @cookies = JSON.parse(file.read)
    end
    @cookies.each do |ck|
      @agent_head.cookie_jar << Mechanize::Cookie.new(ck)
      @agent_tail.cookie_jar << Mechanize::Cookie.new(ck)
    end
  end

  def get_search_param
    re = ''
    re += "&f_cats=#{search_options(:type_bitset)}"
    re += "&f_search=#{search_options(:filter)}" if (search_options(:filter) || '').length > 0
    re
  end

  def get_advsearch_param
    re  = '&advsearch=1'
    re += '&f_sname=on' if search_options(:s_name)
    re += '&f_stags=on' if search_options(:s_tags)
    re += '&f_sh=on'    if search_options(:s_deleted)
    re += "&f_sr=on&f_srdd=#{search_options(:min_star)}" if search_options(:min_star) > 1
    re += "&f_sp=on&f_spf=#{search_options(:page_between).first}&f_spt=#{search_options(:page_between).last}"
    re
  end

  def get_page_url(page_id=0)
    "https://e-hentai.org/?page=#{page_id}#{get_search_param()}#{get_advsearch_param()}"
  end

  def get_total_number()
    puts @current_doc.css("[@class='ip']")[0].text
    return false unless @current_doc.css("[@class='ip']")[0].text.match(TotalResult_regex)
    @total_num = $1.tr(',','').strip.to_i
  end

  def start_scan
    _url = get_page_url()
    $download_targets = []
    $failed_galleries = []
    $failed_images    = []
    @new_json = []
    @agent_head.new_json = @agent_tail.new_json = @new_json

    eval_action("Getting `#{_url}`...") do
      @current_doc = @agent_head.fetch(_url)
    end
    get_total_number()
    request_continue("#{SPLIT_LINE}Searched with #{@total_num} results")

    @prev_size = @existed_json.size
    collect_metas()
    sleep(1) while @agent_head.working? || @agent_tail.working?
    output_metas()
    
    return if @config[:meta_only]
    start_download()
    sleep(1) while @agent_head.working? || @agent_tail.working?
    puts("Download completed!")
    process_failed_downloads()
  end

  def collect_metas
    $existed_gal_cnt = 0
    total_pages = (@total_num / 25.0).ceil
    puts "Total pages: #{total_pages}"
    mid = total_pages / 2
    @agent_head.end_page = @agent_tail.start_page = mid
    @agent_tail.end_page = total_pages
    puts "Head: page#{@agent_head.start_page}~page#{mid}; Tail: page#{mid}~page#{total_pages}"
    Thread.new{@agent_tail.start_scan()}
    @agent_head.start_scan()
    sleep(1)
  end

  def output_metas
    puts "#{SPLIT_LINE}Collected total of #{@new_json.size} new gallery infos (#{$existed_gal_cnt} existed)"
    @existed_json += @new_json
    @new_json = nil
    File.open(ResultJsonFilename, 'w') do |file|
      file.puts(JSON.pretty_generate(@existed_json))
    end
    puts "Total of #{@existed_json.size} gallery infos saved."
  end

  def start_download
    _len = $download_targets.size
    puts("#{SPLIT_LINE}Start downloading total of #{_len} galleries")
    $download_targets.each do |info|
      prev_failed = $failed_images.size
      _start_download(info)
      puts "#{SPLIT_LINE}Download completed with #{$failed_images.size - prev_failed} failed\n"
    end
  end

  def _start_download(info)
    download_gallery(info)
    sleep(1) while @agent_head.working? || @agent_tail.working?
    dump_cur_meta()
  end

  def on_gallery_failed
    puts "Failed to get gallery: #{@parnet_url}"
    $failed_galleries << FailedGallery.new(@cur_gid, @cur_token, @cur_folder)
    @flag_failed = true
  end

  def failed?
    !@flag_failed
  end

  def download_gallery(info)
    @flag_failed = false
    @cur_meta    = {}
    @cur_folder  = DownloadFolder.dup
    @cur_gid, @cur_token = info['gid'], info['token']
    build_gallery_folder()
    @parnet_url = "#{BaseURL}#{@cur_gid}/#{@cur_token}?nw=session"
    @current_doc = @agent_head.fetch(@parnet_url)
    if @current_doc.search(".gpc").text.match(TotalImg_regex)
      @total_cnt = $2.tr(',','').to_i
      puts "Total images: #{@total_cnt}"
    else
      return on_gallery_failed()
    end
    first_page = @current_doc.links_with(href: Regexp.new("#{info['gid']}-1")).first.uri
    @current_doc = @agent_head.fetch(first_page, fallback: method(:on_gallery_failed))
    last_page = @current_doc.links_with(href: Regexp.new("#{info['gid']}-#{@total_cnt}")).first.uri
    mid = (@total_cnt / 2).to_i
    @agent_head.start_page = 1
    @agent_tail.start_page = @total_cnt
    @agent_head.end_page   = mid
    @agent_tail.end_page   = mid + 1
    Thread.new{@agent_tail.start_download(last_page, @cur_gid, @cur_token)} if @total_cnt > 1
    @agent_head.start_download(first_page, @cur_gid, @cur_token)
    sleep(1)
  end

  def get_folder_name
    folder_name = (@config[:english_title] ? @cur_meta['title'] : @cur_meta['title_jpn']).tr('\\/:*?\"><|','')
    return "#{DownloadFolder}#{folder_name}/"
  end

  def build_gallery_folder()
    @cur_meta = request_gallery_meta([[@cur_gid, @cur_token]]).first
    @cur_folder = get_folder_name()
    Dir.mkdir(@cur_folder) unless File.exist?(@cur_folder)
  end

  def dump_cur_meta
    if File.exist?("#{@cur_folder}/_meta.json")
      puts "`#{@cur_folder}/_meta.json` already exists, skipping"
      return
    end
    File.open("#{@cur_folder}/_meta.json", 'w'){|f| f.puts(JSON.pretty_generate(@cur_meta))}
  end

  def load_failed_info
    if File.exist?("failedG.dat")
      info = []
      begin
        File.open("failedG.dat", 'rb') do |file|
          info = Marshal.load(file)
        end
        $failed_galleries += info
      rescue Exception => err
        warning("An error occurred while loading failed gallery info!", err)
      end
    end
    if File.exist?("failedI.dat")
      info = []
      begin
        File.open("failedG.dat", 'rb') do |file|
          info = Marshal.load(file)
        end
        $failed_images += info
      rescue Exception => err
        warning("An error occurred while loading failed image info!", err)
      end
    end
    $failed_galleries.uniq!{|obj| obj.page_url}
    $failed_images.uniq!{|obj| obj.gid}
  end

  def dump_failed_info
    load_failed_info()
    File.open("failedG.dat") do |file|
      info = Marshal.dump($failed_galleries, file)
    end
    File.open("failedI.dat") do |file|
      info = Marshal.load($failed_images, file)
    end
  end

  def process_failed_downloads
    return if $failed_galleries.size == 0 && $failed_images.size == 0
    puts("Failed gallery: #{$failed_galleries.size}")
    puts("Failed images: #{$failed_images.size}")
    print("#{SPLIT_LINE}Retry these downloads? (Y/N): ")
    request_continue(nil, no: method(:process_save_failed))
    retry_failed_downloads()
  end

  def process_save_failed
    print("#{SPLIT_LINE}Save failed downloads for further retry? (Y/N): ")
    eval_action("Saving..."){dump_failed_info()}
  end

  def retry_failed_downloads
    load_failed_info()
    tmp_failed = $failed_galleries.dup
    $failed_galleries = []
    tmp_failed.each do |info|
      _start_download(info)
    end
    _len = $failed_images.size
    return if _len == 0
    tmp_failed = $failed_images.dup
    $failed_images = []
    mid = (_len / 2).to_i
    if mid >= 1
      Thread.new{@agent_tail.redownload_images(tmp_failed[mid..._len])}
    end
    @agent_head.redownload_images(tmp_failed[0...max(1, mid)])
    sleep(1) while @agent_head.working? || @agent_tail.working?
    process_failed_downloads()
  end
end

EHentaiDownloader.initialize
EHentaiDownloader.start_scan

# File.open("tmp.txt", 'w') do |file|
#   file.puts JSON.pretty_generate()
# end
# resp = %{{"gmetadata":[{"gid":618395,"token":"0439fa3666","archiver_key":"434532--ab734919da6eed988d994ad9efe7b3b72a0d4832","title":"(Kouroumu 8) [Handful\u2606Happiness! (Fuyuki Nanahara)] TOUHOU GUNMANIA A2 (Touhou Project)","title_jpn":"(\u7d05\u697c\u59228) [Handful\u2606Happiness! (\u4e03\u539f\u51ac\u96ea)] TOUHOU GUNMANIA A2 (\u6771\u65b9Project)","category":"Non-H","thumb":"https:\/\/ehgt.org\/14\/63\/1463dfbc16847c9ebef92c46a90e21ca881b2a12-1729712-4271-6032-jpg_l.jpg","uploader":"avexotsukaai","posted":"1376143500","filecount":"20","filesize":51210504,"expunged":false,"rating":"4.52","torrentcount":"0","tags":["parody:touhou project","character:hong meiling","character:marisa kirisame","character:reimu hakurei","character:sanae kochiya","character:youmu konpaku","group:handful happiness","artist:nanahara fuyuki","artbook","full color"]}]}}
# metas = JSON.load(resp)['gmetadata']
# metas.each do |mdat|
#   mdat.each do |k, v|
#     puts "#{k}: #{v}"
#   end
# end
# puts EHentaiDownloader.config
# puts EHentaiDownloader.get_page_url
