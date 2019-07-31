module EHentaiDownloader
  mattr_reader :agent_head, :agent_tail, :config, :cur_folder, :total_num
  mattr_reader :existed_json, :cookies, :current_doc, :new_json, :worker

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
    $fetched_cnt = 0
    $failed_images    ||= []
    $failed_galleries ||= []
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
        :disable_default_filter => true,
      },

      :english_title          => false,
      :download_original      => false,
      :meta_only              => false,
      :fetch_loose_threshold  => 2,
      :fetch_sleep_time       => 10,
      :fetch_sleep_rrange     => 3,
      :set_start_page         => false,
    }
    load_config_files()
    @agent_head.search_param = "#{get_search_param()}#{get_advsearch_param()}"
    @agent_tail.search_param = "#{get_search_param()}#{get_advsearch_param()}"
    load_existed_meta()
    @existed_json ||= []
    @agent_head.existed_json = @existed_json
    @agent_tail.existed_json = @existed_json
  end

  def load_config_files
    eval_action("Loading config file..."){load_config()}
    eval_action("Loading cookie..."){load_cookie()}
  end

  def load_existed_meta
    return unless File.exist?(ResultJsonFilename)
    eval_action("Loading exited meta infos...") do
      File.open(ResultJsonFilename, 'r') do |file|
        @existed_json = JSON.load(file)
      end
    end
  end

  def merge_meta(metas)
    @existed_json += metas
    @existed_json.uniq!{|obj| obj['gid']}
  end

  def search_options(sym=nil)
    return @config[:search_options] if sym.nil?
    return @config[:search_options][sym]
  end

  def get_config_hash(parent=@config)
    re = '_cfg_'
    parent.each do |k, v|
      if v.respond_to?(:each)
        re += get_config_hash(v)
      else
        re += k.to_s + v.to_s
      end
    end
    return Digest::SHA256.hexdigest(re)
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
      $fetch_loose_threshold = @config[:fetch_loose_threshold]
      $fetch_sleep_time      = @config[:fetch_sleep_time]
      $fetch_sleep_rrange    = @config[:fetch_sleep_rrange]
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
    puts "#{@cookies.size} cookies loaded"
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
    re += "&f_sfl=on&f_sfu=on&f_sft=on" if search_options(:disable_default_filter)
    re
  end

  def get_page_url(page_id=0)
    "https://e-hentai.org/?page=#{page_id}#{get_search_param()}#{get_advsearch_param()}"
  end

  def get_total_number()
    if @current_doc.links.size == 0
      puts @current_doc.body
      puts "Traffic overloaded...please wait for the ban exipres or switch your cookie."
      exit()
    end
    puts @current_doc.css("[@class='ip']")[0].text
    return false unless @current_doc.css("[@class='ip']")[0].text.match(TotalResult_regex)
    @total_num = $1.tr(',','').strip.to_i
  end

  def start_scan
    init_collect_members()
    _url = get_page_url()

    eval_action("") do
      @current_doc = @agent_head.fetch(_url)
    end
    get_total_number()
    return unless prepare_collect_metas()
    collect_metas()
    sleep(1) while @agent_head.working? || @agent_tail.working?
    output_metas()
    puts "#{SPLIT_LINE}Time taken: #{to_readable_time_distance(Time.now - $meta_start_time)}"

    return if @config[:meta_only]
    start_download()
    sleep(1) while @agent_head.working? || @agent_tail.working?
    puts("Download completed!")
    process_failed_downloads()
  end

  def prepare_collect_metas
    _continue = true
    request_continue("#{SPLIT_LINE}Searched with #{@total_num} results\nContinue?", no: Proc.new{_continue = false})
    return false unless _continue
    $meta_start_time = Time.now
    @worker = Thread.new{@agent_tail.start_scan(1)}
    @agent_head.start_scan(0)
    return true
  end

  def init_collect_members
    $download_targets = []
    $failed_galleries = []
    $failed_images    = []
    @new_json = []
    @agent_head.new_json = @agent_tail.new_json = @new_json
    $existed_gal_cnt = 0
  end

  def collect_metas
    @agent_head.start_page = nil
    total_pages = (@total_num / 25.0).ceil
    puts "Total pages: #{total_pages}"
    if @config[:set_start_page]
      request_continue("Setting scan range manually?", yes: Proc.new{
        _in_st = (input("Start from (#{0}~#{total_pages}): ").to_i rescue nil) until _in_st.is_a?(Numeric)
        _in_ed = (input("End at (#{mid}~#{@agent_tail.end_page}): ").to_i  rescue nil) until _in_ed.is_a?(Numeric)
      })
    end

    if @agent_head.start_page.nil?
      _in_st, _in_ed = 0, total_pages
    end
    mid = total_pages / 2
    @agent_head.start_page = _in_st
    @agent_head.end_page = @agent_tail.start_page = mid
    @agent_tail.end_page = _in_ed
    puts "Head: page#{@agent_head.start_page}~page#{mid}; Tail: page#{mid}~page#{_in_ed}"
    @worker = Thread.new{@agent_tail.start_scan(1)}
    @agent_head.start_scan(0)
    sleep(1)
  end

  def output_oom_metas()
    puts "#{SPLIT_LINE}Collected total of #{@new_json.size} new gallery infos (#{$existed_gal_cnt} existed)"
    puts "Time taken: #{to_readable_time_distance(Time.now - $meta_start_time)}"
    cnt = 0
    cnt+= 1 while File.exist?("_meta_tmp_#{cnt}.json")
    File.open("_meta_tmp_#{cnt}.json", 'w') do |file|
      file.puts(@new_json.to_json)
    end
    puts "Collected meta has output to `_meta_tmp_#{cnt}.json`"
  end

  def output_metas()
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
    tmp_dw_targets = $download_targets.dup
    tmp_dw_targets.each do |info|
      prev_failed = $failed_images.size
      _start_download(info)
      puts "#{SPLIT_LINE}Download completed with #{$failed_images.size - prev_failed} failed\n"
    end
  end

  def _start_download(info)
    begin
      download_gallery(info)
    rescue SystemExit, Interrupt => err
      sleep(3600) until Thread.current == ::MainThread
      raise err
    rescue Exception => err
      warning("Unhandled excpetion while downloading gallery")
      $failed_galleries << FailedGallery.new(@cur_gid, @cur_token, nil)
      @flag_failed = true
    end
    sleep(1) while !@flag_failed && @agent_head.working? || @agent_tail.working?
    if current_gallery_completed?
      puts "OK"
      $download_targets.delete({'gid' => @cur_gid, 'token' => @cur_token})
    else
      dump_download_worker_progress()
    end
    $worker_cur_url = ['', '']
  end

  def dump_download_worker_progress
    return if $worker_cur_url.inject(''){|r,s|r + s.to_s}.strip.length == 0
    eval_action("Dumping worker progress data...") do
      $worker_cur_url.collect!{|uri| uri.to_s}
      puts "\n#{$worker_cur_url}"
      File.open("#{@cur_folder}/_progress.dat", 'wb'){|f| Marshal.dump($worker_cur_url, f)}
    end
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
    @cur_gid, @cur_token = info['gid'], info['token']
    @cur_meta    = request_gallery_meta([[@cur_gid, @cur_token]]).first
    @cur_meta['filecount'] = @cur_meta['filecount'].tr(',','').to_i
    @cur_folder  = build_gallery_folder()
    dump_cur_meta()
    unless gallery_download_needed?
      puts "#{@cur_folder} has already downloaded all files, skip"
      return
    end
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
    # todo: change image scan method to quickly check existed images
    @agent_head.start_page = 1
    @agent_tail.start_page = @total_cnt
    @agent_head.end_page   = mid
    @agent_tail.end_page   = mid + 1
    $worker_cur_url = ['', '']
    @worker = Thread.new{@agent_tail.start_download(1, last_page, @cur_gid, @cur_token)} if @total_cnt > 1
    @agent_head.start_download(0, first_page, @cur_gid, @cur_token)
    sleep(1)
    if @agent_head.cur_page == @agent_head.end_page && @agent_tail.cur_page == @agent_tail.end_page
      $worker_cur_url = ['', '']
      @agent_head.clear_progress()
    end
  end

  def get_folder_name
    if !@config[:english_title] && @cur_meta['title_jpn'].strip.length > 3
      folder_name = @cur_meta['title_jpn']
    else
      folder_name = @cur_meta['title']
    end
    folder_name.tr!('\\/:*?\"><|','')
    return "#{DownloadFolder}#{folder_name}/"
  end

  def build_gallery_folder()
    @cur_folder = get_folder_name()
    Dir.mkdir(@cur_folder) unless File.exist?(@cur_folder)
    return @cur_folder
  end

  def dump_cur_meta
    if File.exist?("#{@cur_folder}/_meta.json")
      puts "`#{@cur_folder}/_meta.json` already exists, skipping"
      return
    end
    File.open("#{@cur_folder}/_meta.json", 'w'){|f| f.puts(JSON.pretty_generate(@cur_meta))}
  end

  def current_gallery_completed?
    file_cnt = Dir.entries("#{@cur_folder}").select{|f| f.end_with?('.jpg')}.size
    puts "#{SPLIT_LINE}`#{@cur_folder}` has #{file_cnt}/#{@cur_meta['filecount']} files downloaded."
    return file_cnt == @cur_meta['filecount']
  end

  def gallery_download_needed?
    return false if current_gallery_completed?
    return true
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
        File.open("failedI.dat", 'rb') do |file|
          info = Marshal.load(file)
        end
        $failed_images += info
      rescue Exception => err
        warning("An error occurred while loading failed image info!", err)
      end
    end
    $failed_galleries.uniq!{|obj| obj.gid}
    $failed_images.uniq!{|obj| obj.page_url}
  end

  def dump_failed_info
    load_failed_info()
    File.open("failedG.dat", 'wb') do |file|
      info = Marshal.dump($failed_galleries, file)
    end
    File.open("failedI.dat", 'wb') do |file|
      info = Marshal.dump($failed_images, file)
    end
  end

  def process_failed_downloads
    return if $failed_galleries.size == 0 && $failed_images.size == 0
    puts("Failed gallery: #{$failed_galleries.size}")
    puts("Failed images: #{$failed_images.size}")
    request_continue("#{SPLIT_LINE}Retry these downloads?", no: method(:process_save_failed))
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
    @agent_head.redownload_images(tmp_failed[0...[1, mid].max])
    sleep(1) while @agent_head.working? || @agent_tail.working?
    process_failed_downloads()
  end

  def resume_download(dat)
    puts "Resume download..."
    EHentaiDownloader.search_options[:filter] = dat[:filter]
    $download_targets = dat[:targets]
    start_download()
    process_failed_downloads()
  end

  def get_meta_progress
    agents = [@agent_head, @agent_tail]
    re = []
    $worker_cur_url.collect!{|s| s == '' ? nil : s}
    agents.each do |agent|
      url = ($worker_cur_url[agent.worker_id] || agent.current_doc.uri.to_s rescue nil)
      re << {
        :sparam   => agent.search_param,
        :start    => agent.start_page,
        :end      => agent.end_page,
        :cur      => agent.cur_page
      }
    end
    return re
  end

  def resume_collect(dat)
    eval_action("Resume collecting...\n") do 
      agents = [@agent_head, @agent_tail]
      agents.each_with_index do |a, i|
        a.search_param = dat[:progress][i][:sparam]
        a.start_page   = dat[:progress][i][:start]
        a.end_page     = dat[:progress][i][:end]
        a.cur_page     = dat[:progress][i][:cur]
        puts "Loaded with searching `#{a.search_param}`"
        puts "#{a.start_page} ~ #{a.end_page} (at #{a.cur_page })"
      end
    end
    init_collect_members()
    @total_num = dat[:total_num] || 0
    return unless prepare_collect_metas()
    sleep(1)
    sleep(1) while @agent_head.working? || @agent_tail.working?
    output_metas()
    puts "#{SPLIT_LINE}Time taken: #{to_readable_time_distance(Time.now - $meta_start_time)}"
  end
end