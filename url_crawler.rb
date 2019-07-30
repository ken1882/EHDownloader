# -*- coding: utf-8 -*-
$:.unshift File.dirname($0)

VERSION = "0.1.0"
SPLIT_LINE = '-'*21 + 10.chr

FailedImage   = Struct.new(:page_url, :id, :folder, :hd)
FailedGallery = Struct.new(:gid, :token, :folder)
MainThread    = Thread.current
DownloadFolder = "Downloads/"
ENV['SSL_CERT_FILE'] = "cacert.pem"
VK_F5 = 0x74

$fetch_loose_threshold = 2
$fetch_sleep_time      = 10
$fetch_sleep_rrange    = 3
$mutex = Mutex.new
$fetched_cnt = 0
$worker_cur_url = ['', '']

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
require 'digest'
require 'lib/util'
require 'lib/core_ext'
require 'lib/agent'
require 'lib/ehdownloader'

$running = true
Dir.mkdir("tmp/") unless File.exist?("tmp/")
Dir.mkdir(DownloadFolder) unless File.exist?(DownloadFolder)

def start
  while $running
    begin
      puts SPLIT_LINE
      puts "Select functions:"
      puts "[0] Exit"
      puts "[1] Download from `conig.txt`"
      puts "[2] Retry failed downloads"
      puts "[3] Resume a download"
      _in = ''
      until [0, 1, 2, 3].include?(_in)
        print("#{SPLIT_LINE}>> ")
        _in = STDIN.getch.to_i rescue nil
      end
      puts _in, SPLIT_LINE
      EHentaiDownloader.initialize
      case _in
      when 0; puts("Bye!"); exit();
      when 1; EHentaiDownloader.start_scan();
      when 2; process_failed_downloads();
      when 3; process_download_resume();
      end
    rescue SystemExit, Interrupt
      Thread.kill_all()
      eval_action("Terminating singal received, dumping failed download info") do
        EHentaiDownloader.dump_failed_info()
      end
      if meta_collecting?
        puts "#{SPLIT_LINE}An attempt to abort is detected but meta is still collecting,"
        print "do you want to dump them to a tmp file? (Y/N)"
        request_continue(nil, yes: Proc.new{EHentaiDownloader.output_oom_metas()})
      elsif downloading?
        puts "#{SPLIT_LINE}An attempt to abort is detected but gallery is still downloading,"
        print "do you want to resume the download later? (Y/N)"
        rescue_downloads()
      end
      exit_exh()
    end
  end
end

def meta_collecting?
  return (EHentaiDownloader.new_json || []).size > 0
end

def downloading?
  return $worker_cur_url.any?{|ss| ss.to_s.length > 10}
end

def rescue_downloads
  request_continue(nil, yes: Proc.new{
    EHentaiDownloader.dump_download_worker_progress()
    _filename = "tmp/dw_#{EHentaiDownloader.get_config_hash()}.dat"
    if File.exist?(_filename)
      print("#{_filename} already exists, overwrite? (Y/N): ")
      request_continue(nil, yes: method(:dump_download_status))
    else
      dump_download_status(_filename)
    end
  });
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
  download_data = load_resume_files()
  _len = download_data.size
  return if _len == 0
  _selected = -1
  cur_page = 0
  top_index, bot_index = 0, [_len, 10].min
  while _selected == -1
    top_index = 10 * cur_page
    bot_index = [10 * (cur_page + 1), _len].min
    puts "#{SPLIT_LINE}List #{top_index+1}~#{bot_index} of #{_len} results\n#{SPLIT_LINE.chomp}"
    cnt = 0
    accepted_input = ['Q']
    download_data[top_index...bot_index].each do |dat|
      puts "[#{cnt}] #{dat[:filename]} (filter = #{dat[:filter]}"
      accepted_input << cnt.to_s
      cnt += 1
    end
    accepted_input << 'A' if cur_page > 0
    accepted_input << 'D' if bot_index < _len
    puts "#{SPLIT_LINE}#{'Q: quit'}#{' A: prev page' if cur_page > 0}#{' D: next page' if bot_index < _len}"
    print ">> "
    _in = ''
    _in = STDIN.getch.upcase until accepted_input.include?(_in)
    puts _in
    case _in
    when 'A'; cur_page -= 1;
    when 'D'; cur_page += 1;
    when 'Q'; exit();
    when /\d+/; _selected = _in.to_i + cur_page * 10;
    end
  end # while not selected
  EHentaiDownloader.resume_download(download_data[_selected])
end

def load_resume_files
  files = Dir.glob("tmp/*.dat")
  _len = files.size
  puts "#{_len} files found"
  return [] if _len == 0
  re = []
  files.each{|f| File.open(f, 'rb'){|_f| re << (Marshal.load(_f) rescue nil)}}
  puts "#{_len - re.size} files failed to load"
  return re.compact
end

start()