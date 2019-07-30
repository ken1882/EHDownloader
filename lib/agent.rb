class Agent < Mechanize
  attr_reader :current_doc, :existed_json, :flag_working, :new_json
  attr_accessor :failed, :search_param
  attr_accessor :start_page, :end_page, :cur_page

  def initialize(*args)
    @current_doc = nil
    @flag_working = false
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
    $mutex.synchronize{$fetched_cnt += 1}
    if !kwargs[:no_loose] && $fetch_loose_threshold > 0 && $fetched_cnt >= $fetch_loose_threshold
      _slpt = $fetch_sleep_time + rand($fetch_sleep_rrange) + rand().round(2)
      puts("\nFetched count > #{$fetch_loose_threshold}, sleep for #{_slpt} seconds to loose traffic")
      $mutex.synchronize{$fetched_cnt = 0}
      sleep(_slpt)
    end
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
      rescue SystemExit, Interrupt => err
        sleep(3600) until Thread.current == ::MainThread
        raise err
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
    @current_doc = check_wait_ban(@current_doc)
    re  = @current_doc.links_with(href: /https:\/\/e-hentai.org\/g\//).uniq{|l| l.href}
    scanned_cnt = 0
    re.each do |link|
      _url = link.href.split('/')
      gid, token = _url[-2].to_i, _url[-1]
      unless EHentaiDownloader.config[:meta_only]
        $mutex.synchronize{$download_targets << {'gid' => gid, 'token' => token}}
      end
      if meta_exist?(gid)
        puts "#{gid}/#{token} is already existed, skipping"
        $mutex.synchronize{$existed_gal_cnt += 1}
        next
      end
      $mutex.synchronize{
        begin
          @new_json << {'gid' => gid, 'token' => token}
        rescue Exception
          @new_json.pop
          puts "Out of memory...output to tmp json file"
          EHentaiDownloader.output_oom_metas()
        end
      }
    end
  end

  def meta_exist?(gid)
    return @existed_json.any?{|obj| obj['gid'] == gid}
  end

  def load_prev_progress
    _url = ''
    puts "#{@cur_folder}/_progress.dat: #{::File.exist?("#{@cur_folder}/_progress.dat")}"
    if ::File.exist?("#{@cur_folder}/_progress.dat")
      ::File.open("#{@cur_folder}/_progress.dat", 'rb') do |file|
        _dat = Marshal.load(file)
        _url = (@end_page > @start_page ? _dat.first : _dat.last)
        puts "Prev progress loaded: #{_url}"
      end
    end
    return _url
  end

  def clear_progress
    return unless ::File.exist?("#{@cur_folder}/_progress.dat")
    ::File.delete("#{@cur_folder}/_progress.dat")
  end

  def start_download(init_url, gid, token)
    @flag_working = true
    @cur_folder = EHentaiDownloader.cur_folder
    @cur_gid, @cur_token = gid, token
    eval_action("Check previous progress...") do 
       _url = load_prev_progress()
       _url = init_url.to_s if _url.length < 10
       @current_doc = fetch(_url, fallback: Proc.new{on_fetch_failed(_url)})
    end
    @cur_page = @current_doc.uri.to_s.split('-').last.to_i
    loop do
      break if @current_doc.nil?
      @cur_parent_url = @current_doc.uri
      dowload_current_image()
      wait4download()
      break if @end_page == @cur_page
      if @end_page > @start_page
        @cur_page += 1
        $worker_cur_url.first = @cur_parent_url.to_s
      elsif @end_page < @start_page
        @cur_page -= 1
        $worker_cur_url.last  = @cur_parent_url.to_s
      end
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
    img = self.fetch(img_url, fallback: Proc.new{on_download_failed(@cur_parent_url)}, no_loose: true)
    unless img.is_a?(::Mechanize::Image)
      warning("Unable to get original image from #{@cur_parent_url}, please check your cookie or download limits!")
      return
    end
    img.save(filename)
    puts "#{filename} saved"
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
      Dir.mkdir(@cur_folder) unless ::File.exist?(@cur_folder)
      dowload_current_image(info.hd)
      wait4download()
    end
  end

end