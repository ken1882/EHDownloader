# -*- coding: utf-8 -*-
$:.unshift File.dirname($0)

VERSION = "0.1.3"
SPLIT_LINE = '-'*21 + 10.chr

if ARGV.include?("-v") || ARGV.include?("--version")
  puts VERSION
  exit()
end

FailedImage   = Struct.new(:page_url, :id, :folder, :hd, :gid, :gtoken)
FailedGallery = Struct.new(:gid, :token, :folder)
MainThread    = Thread.current
DownloadFolder = "Downloads/"
ENV['SSL_CERT_FILE'] = "cacert.pem"

$failed_galleries = []
$failed_images    = []
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
require 'lib/ui_selector'

$running = true
Dir.mkdir("tmp/") unless File.exist?("tmp/")
Dir.mkdir(DownloadFolder) unless File.exist?(DownloadFolder)

def start
  while $running
    begin
      EHentaiDownloader.initialize
      detect_tmp_metas()
      dw_or_mt = EHentaiDownloader.config[:meta_only] ? "Collect metas" : "Download"
      messages = [
        "Exit",
        "#{dw_or_mt} from `conig.txt`",
        "Download from file",
        "Retry failed downloads",
        "Resume a download",
        "Resume a meta collecting",
      ]
      list = messages.collect{|m| UI_Selector::Item.new(m)}
      EHentaiDownloader.initialize
      _in = UI_Selector.start(list: list, head_msg: "Select a function", quit: method(:exit_exh))
      case _in
      when 0; puts("Bye!"); exit_exh();
      when 1; EHentaiDownloader.start_scan();
      when 2; process_input_download();
      when 3; process_failed_downloads();
      when 4; process_download_resume();
      when 5; process_meta_resume();
      end
    rescue SystemExit, Interrupt, Exception => err
      on_unhandled_error(err) unless err.is_a?(SystemExit) || err.is_a?(Interrupt)
      Thread.kill_all()
      if $failed_galleries.size + $failed_images.size > 0
        eval_action("Terminating singal received, dumping failed download info...") do
          EHentaiDownloader.dump_failed_info()
        end
      end
      if meta_collecting?
        puts "#{SPLIT_LINE}An attempt to abort is detected but meta is still collecting,"
        print "do you want to dump them to a tmp file? (Y/N)"
        rescue_metas()
      elsif downloading?
        puts "#{SPLIT_LINE}An attempt to abort is detected but gallery is still downloading,"
        print "do you want to resume the download later? (Y/N)"
        rescue_downloads()
      end
      exit()
    end
  end
end

start()