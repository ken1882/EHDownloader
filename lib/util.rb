require 'win32api'

GetAsyncKeyState = Win32API.new('user32', "GetAsyncKeyState", 'i', 'i')

def key_triggered?(vt)
  return (GetAsyncKeyState.call(vt) & 0x8000) != 0
end

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
    puts("#{err}\n#{SPLIT_LINE}")
    puts("This action will be skipped")
  end
  puts("succeed")
end

# Check if banned, and wait if true
def check_wait_ban(page)
  while page.links.size == 0
    puts "#{SPLIT_LINE}Traffic overloaded! Sleep for 1 hour to wait the ban expires"
    puts "Press `C` to force continue"
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