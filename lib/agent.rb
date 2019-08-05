# -*- coding: utf-8 -*-
class Agent < Mechanize
  attr_reader :current_doc, :existed_json, :flag_working, :new_json, :worker_id
  attr_reader :collected_images
  attr_accessor :failed, :search_param
  attr_accessor :start_page, :end_page, :cur_page

  ImageFileExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webm', 'webp']
  BandwidthExcessedURL = ["https://ehgt.org/g/509.gif", "https://exhentai.org/img/509.gif"]
  BandwidthExcessedImgSize = [425, 750]
  InputFPS = 40

  def initialize(*args)
    @current_doc = nil
    @flag_working = false
    @cur_page = 0
    @search_param = ''
    @start_page = @end_page = 0
    super
  end

  def current_doc=(doc); @current_doc = doc; end

  def working?; @flag_working; end
  def existed_json=(_out)
    return if @existed_json.equal?(_out)
    @existed_json = _out
  end

  def new_json=(_out)
    return if @new_json.equal?(_out)
    @new_json = _out
  end

  def collected_images=(_out)
    return if @collected_images.equal?(_out)
    @collected_images = _out
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
        puts "#{SPLIT_LINE}Terminate singal received!"
        raise err
      rescue Exception => err
        warning("\nAn error occurred during fetch page! #{err}, retrying...(depth=#{depth})")
        sleep(0.3)
      end
    end
    return _doc
  end

  def get_page_url(page_id=0)
    "#{$cur_host}/?page=#{page_id}#{@search_param}"
  end

  def start_scan(_id)
    @worker_id = _id
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
    $worker_cur_url[@worker_id] = @current_doc.uri rescue ''
    @cur_page += 1
  end

  def collect_metas
    @current_doc = check_wait_ban(@current_doc)
    re  = @current_doc.links_with(href: /https:\/\/e(?:-|x)hentai.org\/g\//).uniq{|l| l.href}
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
        _url = _dat[@worker_id]
        puts "Prev progress loaded: #{_url}"
      end
    end
    return _url
  end

  def clear_progress
    return unless ::File.exist?("#{@cur_folder}/_progress.dat")
    ::File.delete("#{@cur_folder}/_progress.dat")
  end

  def start_download(_wid, image_page_links)
    @flag_working = true
    @worker_id    = _wid
    @cur_folder   = EHentaiDownloader.cur_folder
    @cur_gid      = EHentaiDownloader.cur_gid
    @cur_token    = EHentaiDownloader.cur_token
    last_url      = ''
    eval_action("Check previous progress...") do 
      last_url = load_prev_progress()
      last_url = image_page_links.first if last_url.length < 10
    end
    last_url  = nil unless image_page_links.include?(last_url)
    cur_index = image_page_links.index(last_url) || 0
    _len = image_page_links.size
    while cur_index < _len
      link = image_page_links[cur_index]
      @cur_page = link.to_s.split('-').last.to_i
      @cur_parent_url = link.to_s
      $worker_cur_url[@worker_id] = link.to_s
      @current_doc = fetch(link, fallback: Proc.new{on_fetch_failed(link)})
      dowload_current_image()
      wait4download()
      cur_index += 1
    end
    @flag_working = false
  end

  def dowload_current_image(download_hd=EHentaiDownloader.config[:download_original])
    @thread_lock = true
    @flag_download_hd = download_hd
    img_url = nil
    check_wait_limit(@current_doc)
    if download_hd
      img_url = @current_doc.links_with(href: /https:\/\/e(?:-|x)hentai.org\/fullimg.php/).first.href rescue nil
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
    $mutex.synchronize{
      $failed_images << FailedImage.new(parent_url, @cur_page, @cur_folder, @flag_download_hd, @cur_gid, @cur_token)
    }
    return nil
  end

  def download_image_async(img_url)
    file_ext = img_url.split('.').last
    filename = "#{@cur_folder}/#{@cur_page.to_fileid}.#{file_ext}"
    if ::File.exist?(filename)
      return puts("#{filename} already exists, skip")
    end
    img = self.fetch(img_url, fallback: Proc.new{on_download_failed(@cur_parent_url)}, no_loose: true)
    unless img.is_a?(::Mechanize::Image)
      warning("Unable to get original image from #{@cur_parent_url}, please check your cookie or download limits!")
      return unless Thread.current == ::MainThread
      request_continue("Do you want to continue anyway?", no: Proc.new{exit()})
      $mutex.synchronize{
        $failed_images << FailedImage.new(@cur_parent_url, @cur_page, @cur_folder, true, @cur_gid, @cur_token)
      }
      return
    end
    return on_509_fail if is_509_image?(img, img_url)
    img.save(filename)
    puts "#{filename} saved"
  end

  def is_509_image?(img, source_url=nil)
    return false unless source_url && source_url.split('/').last == "509.gif"
    return false unless source_url && source_url.split('.').last == "gif"
    _dimension = get_gif_size(img.body_io)
    return false unless _dimension && _dimension == BandwidthExcessedImgSize
    return true
  end

  def on_509_fail
    puts "#{SPLIT}An 509(Bandwidth limit excessed) image is detected!"
    puts "#{@cur_parent_url} will consider as an failed image"
    $mutex.synchronize{
      $failed_images << FailedImage.new(@cur_parent_url, @cur_page, @cur_folder, true, @cur_gid, @cur_token)
    }
  end

  def wait4download()
    start_time = Time.now
    timeout_duration = EHentaiDownloader.get_timeout_duration()
    puts "Waiting for download (timeout=#{timeout_duration})"
    while @thread_lock
      sleep(0.3)
      if (Time.now - start_time).to_f > timeout_duration
        puts "#{@cur_page} timeouted ( > #{timeout_duration} sec)"
        Thread.kill(@worker)
        $mutex.synchronize{$failed_images << FailedImage.new(@cur_parent_url, @cur_page, @cur_folder)}
        @thread_lock = false
      end
    end
  end

  def get_next_link
    begin
      return @current_doc.links_with(href: Regexp.new("#{@cur_gid}-#{@cur_page}")).first.uri
    rescue Exception => err
      puts "#{err}#{@current_doc.uri}"
      raise err
    end
  end

  def redownload_images(imgs)
    imgs.each_with_index do |info, i|
      begin
        @cur_parent_url = info.page_url
        @cur_page       = info.id
        @cur_folder     = info.folder
        @cur_gid        = info.gid
        @cur_token      = info.gtoken
        @current_doc = fetch(@cur_parent_url, fallback: Proc.new{on_fetch_failed( @cur_parent_url)})
        Dir.mkdir(@cur_folder) unless ::File.exist?(@cur_folder)
        dowload_current_image(info.hd)
        wait4download()
      rescue SystemExit, Interrupt => err
        puts "Termiante singal received, merging retrying images"
        $mutex.synchronize{
          $download_targets ||= []
          $download_targets += imgs[i...imgs.size].collect{|o| {'gid'=>o.gid, 'token'=>o.gtoken} }
          $download_targets.uniq!{|obj| obj['gid']}
        }
        raise err
        break
      end
    end
  end

  def collect_images(wid)
    @flag_working = true
    @worker_id    = wid
    @cur_folder   = EHentaiDownloader.cur_folder
    @cur_gid      = EHentaiDownloader.cur_gid
    @cur_token    = EHentaiDownloader.cur_token
    @image_url_regex  = Regexp.new("#{@cur_gid}-(\\d+)")
    gallery_base_link = "#{$cur_host}/g/#{@cur_gid}/#{@cur_token}/"
    @cur_page = @start_page
    @last_page_content_hash = Digest::SHA256.hexdigest("_base_")
    loop do
      _next_url = "#{gallery_base_link}?p=#{@cur_page}"
      @current_doc = fetch(_next_url, fallback: Proc.new{on_fetch_failed(_next_url)})
      collect_undownloaded_images()
      break if @current_doc.nil? || @cur_page == @end_page
      @cur_page += (@end_page > @start_page ? 1 : -1)
    end
    @flag_working = false
  end

  def collect_undownloaded_images
    collected_cnt = 0
    cur_page_content_hash = ''
    @current_doc.links_with(href: @image_url_regex).uniq{|s| s.href}.each do |link|
      img_id = link.href.split('-').last.to_i.to_fileid
      cur_page_content_hash += "#{img_id}"
      img_filenames = ImageFileExtensions.collect{|ext| "#{@cur_folder}/#{img_id}.#{ext}"}
      if (_n = img_filenames.index{|fs| ::File.exist?(fs)})
        puts "#{img_filenames[_n]} already existed, skip"
        next
      end
      collected_cnt += 1
      $mutex.synchronize{@collected_images << link.href.to_s}
    end
    cur_page_content_hash = Digest::SHA256.hexdigest(cur_page_content_hash)
    puts "#{collected_cnt} image meta collected"
    if cur_page_content_hash == @last_page_content_hash
      puts "Duplicated website page fetch detected! Abort collecting"
      @cur_page = @end_page
    end
    @last_page_content_hash = cur_page_content_hash
  end

  # Check if banned, and wait if true
  def check_wait_ban(page)
    delta_sec = 1.0 / InputFPS
    while page.links.size == 0
      puts "#{SPLIT_LINE}Traffic overloaded! Sleep for 1 hour to wait the ban expires"
      puts "Press `F5` to force continue"
      waited = 0
      while waited < 60 * 60
        sleep(delta_sec)
        waited += delta_sec
        if key_triggered?(VK_F5)
          puts "Trying reconnect..."
          page = fetch(page.uri)
          if page.links.size == 0
            puts "Ban still remains! Response Body:"
            puts page.body + 10.chr
          else
            puts "Succeed!"
            break
          end
        end
      end # while waiting
      page = fetch(page.uri)
    end
    return page
  end

  def check_wait_limit(page)
    delta_sec = 1.0 / InputFPS
    loop do
      img_link = page.css("[@id='img']").first.attr('src') 
      break unless BandwidthExcessedURL.include?(img_link.to_s)
      puts "#{SPLIT_LINE}Your limit of viewing gallery image has reached. Program will pause for 1 hour."
      puts "Or press `F5` to force continue"
      waited = 0
      while waited < 60 * 60
        sleep(delta_sec)
        waited += delta_sec
        if key_triggered?(VK_F5)
          puts "Trying reconnect..."
          page = fetch(page.uri)
          img_link = page.css("[@id='img']").first.attr('src')
          if BandwidthExcessedURL.include?(img_link.to_s)
            puts "The limit still has reached the maximum"
          else
            puts "Succeed!"
            break
          end
        end
      end # while waiting
      page = fetch(page.uri)
    end
    return page
  end

end