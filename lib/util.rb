require 'win32api'

GetAsyncKeyState = Win32API.new('user32', "GetAsyncKeyState", 'i', 'i')
VK_F5 = 0x74

$key_states = []
$key_called_cnt = 0
def key_triggered?(vt)
  $key_called_cnt += 1
  re = (GetAsyncKeyState.call(vt) & 0x8000) != 0
  $key_states[vt] = true if re
  if $key_called_cnt > 3
    $key_states = []
  end
  return re || $key_states[vt]
end

def warning(*args)
  return if $no_warning
  args.unshift("[Warning]:").push(SPLIT_LINE)
  puts(*args)
end

# Continue program or exit
def request_continue(msg=nil, **kwargs)
  print("#{msg} (Y/N): ") unless msg.nil?
  _ch = ''
  _ch = STDIN.getch.upcase until _ch == 'Y' || _ch == 'N'
  puts _ch
  if _ch == 'N'
    kwargs[:no].call() if kwargs[:no]
  elsif kwargs[:yes]
    kwargs[:yes].call()
  end
end

def report_exception(error)
  backtrace = error.backtrace
  error_line = backtrace.first
  backtrace[0] = ''
  err_class = " (#{error.class})"
  back_trace_txt = backtrace.join("\n\tfrom ")
  error_txt = sprintf("%s %s %s %s %s %s",error_line, ": ", error.message, err_class, back_trace_txt, "\n" )
  return error_txt
end

alias exit_exh exit
def exit(*args)
  puts("Press any key to exit...")
  STDIN.getch
  exit_exh(*args)
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
    puts("#{report_exception(err)}\n#{SPLIT_LINE}")
    puts("This action will be skipped")
  end
  puts("succeed")
end

# Check if banned, and wait if true
def check_wait_ban(page)
  while page.links.size == 0
    puts "#{SPLIT_LINE}Traffic overloaded! Sleep for 1 hour to wait the ban expires"
    puts "Press `F5` to force continue"
    watied = 0
    while watied < 60 * 60
      sleep(0.05)
      watied += 0.05
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
  loop do
    img_link = page.css("[@id='img']").first.attr('src')  
    break unless img_link.to_s == "https://ehgt.org/g/509.gif"
    puts "#{SPLIT_LINE}Your limit of viewing gallery image has reached. Program will pause for 1 hour."
    puts "Or press `F5` to force continue"
    watied = 0
    while watied < 60 * 60
      sleep(0.05)
      watied += 0.05
      if key_triggered?(VK_F5)
        puts "Trying reconnect..."
        page = fetch(page.uri)
        if page.css("[@id='img']").first.attr('src') == "https://ehgt.org/g/509.gif"
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

def input(msg='')
  print(msg)
  return STDIN.gets.chomp
end

def to_readable_time_distance(delta_sec)
  seconds = delta_sec % 60
  delta_sec = delta_sec.to_i
  minutes = delta_sec / 60
  hours   = minutes / 60; minutes %= 60;
  days    = hours / 24; hours %= 24;
  return sprintf("#{days} days, %02d:%02d:%.3f", hours, minutes, seconds)
end

def meta_collecting?
  return EHentaiDownloader.config[:meta_only] && (EHentaiDownloader.new_json || []).size > 0
end

def downloading?
  return $worker_cur_url.any?{|ss| ss.to_s.length > 10}
end

def rescue_metas
  request_continue(nil, yes: Proc.new{
    EHentaiDownloader.output_oom_metas()
    _filename = "tmp/mt_#{EHentaiDownloader.get_config_hash()}.dat"
    if File.exist?(_filename)
      request_continue("#{_filename} already exists, overwrite?", yes: Proc.new{dump_meta_status(_filename)})
    else
      dump_meta_status(_filename)
    end
  })
end

def rescue_downloads
  request_continue(nil, yes: Proc.new{
    EHentaiDownloader.dump_download_worker_progress()
    _filename = "tmp/dw_#{EHentaiDownloader.get_config_hash()}.dat"
    if File.exist?(_filename)
      request_continue("#{_filename} already exists, overwrite?", yes: Proc.new{dump_download_status(_filename)})
    else
      dump_download_status(_filename)
    end
  });
end

def dump_meta_status(_filename)
  File.open(_filename, 'wb') do |file|
    Marshal.dump({
      :total_num => EHentaiDownloader.total_num,
      :filter   => EHentaiDownloader.search_options(:filter), 
      :progress => EHentaiDownloader.get_meta_progress(),
      :filename => _filename
    }, file)
  end
end

def dump_download_status(_filename)
  File.open(_filename, 'wb') do |file|
    Marshal.dump({
      :filter => EHentaiDownloader.search_options(:filter), 
      :targets => $download_targets, 
      :filename => _filename
    }, file)
  end
end

def process_failed_downloads
  EHentaiDownloader.load_failed_info()
  if $failed_galleries.size == 0 && $failed_images.size == 0
    puts("No failed downloads found")
    return
  end
  EHentaiDownloader.process_failed_downloads()
end

def process_download_resume()
  download_data = load_download_resume_files()
  _len = download_data.size
  return if _len == 0
  list = download_data.collect do |dat|
    UI_Selector::Item.new("#{dat[:filename]} (filter = #{dat[:filter]}")
  end
  _selected = UI_Selector.start(list: list, head_msg: "Select a file...", quit: Proc.new{})
  EHentaiDownloader.resume_download(download_data[_selected]) if _selected
end

def load_download_resume_files
  files = Dir.glob("tmp/dw*.dat")
  files.sort_by!{|f| -File.mtime(f).to_f}
  _len = files.size
  puts "#{_len} files found"
  return [] if _len == 0
  re = []
  files.each{|f| File.open(f, 'rb'){|_f| re << (Marshal.load(_f) rescue nil)}}
  puts "#{_len - re.size} files failed to load"
  return re.compact
end

def process_meta_resume
  meta_data = load_meta_resume_files()
  _len = meta_data.size
  return if _len == 0
  list = meta_data.collect do |dat|
    UI_Selector::Item.new("#{dat[:filename][0..15]}...dat (filter = #{dat[:filter]}")
  end
  _selected = UI_Selector.start(list: list, head_msg: "Select a file...", quit: Proc.new{})
  EHentaiDownloader.resume_collect(meta_data[_selected]) if _selected
end

def load_meta_resume_files
  files = Dir.glob("tmp/mt*.dat")
  files.sort_by!{|f| -File.mtime(f).to_f}
  _len = files.size
  puts "#{_len} files found"
  return [] if _len == 0
  re = []
  files.each{|f| File.open(f, 'rb'){|_f| re << (Marshal.load(_f) rescue nil)}}
  puts "#{_len - re.size} files failed to load"
  return re.compact
end

def process_input_download
  filename = "targets.txt"
  unless File.exist?(filename)
    puts "#{filename} not found!"
  end
  $download_targets ||= []
  File.open(filename, 'r') do |file|
    file.read().split(/[\r\n]+/).each do |line|
      next unless line.match(/https:\/\/e-hentai.org\/g\/(\d+)\/(.*)/)
      gid, token = $1.to_i, $2
      token.chomp!('/') until token[-1] != '/'
      puts("line loaded with gid: #{gid} and token: #{token}")
      $download_targets << {'gid' => gid, 'token' => token}
    end
  end
  return puts "Nothing to download!" if $download_targets.size == 0
  EHentaiDownloader.search_options[:filter] = "(Download from file input)"
  EHentaiDownloader.start_download()
end

def on_unhandled_error(err)
  puts "#{SPLIT_LINE}An unhandled error occurs! Please submit to author in order to resolve this issue"
  puts report_exception(err)
  puts SPLIT_LINE
end

def detect_tmp_metas
  files = Dir.glob("_meta_tmp_*.json")
  return if files.size == 0
  puts "#{SPLIT_LINE}Detected #{files.size} of tmp meta files"
  request_continue("Do you wish to merge them?", yes: Proc.new{
    EHentaiDownloader.load_existed_meta()
    new_json = []
    files.each do |file|
      begin
        File.open(file, 'r'){|f| new_json += JSON.load(f)}
      rescue Exception => err
        puts "#{err} while loading #{file}, skip"
      end
    end
    puts "#{new_json.size} gallery info loaded from tmp files, merging..."
    before = EHentaiDownloader.existed_json.size
    EHentaiDownloader.merge_meta(new_json)
    after  = EHentaiDownloader.existed_json.size
    puts "#{after - before} new gallery info loaded"
    files.each{|f| File.delete(f)}
  })
end