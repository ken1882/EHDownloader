module UI_Selector
  Item = Struct.new(:message, :action)

  mattr_reader :list
  mattr_accessor :head_message, :tail_message, :quit_action

  module_function

  def start(**options)
    @list = options[:list]
    @head_message = options[:head_msg] || ''
    @tail_message = options[:tail_msg] || ''
    @quit_action  = options[:quit] 
    show()
  end

  def show
    _selected = -1
    _len = @list.size
    cur_page = 0
    top_index, bot_index = 0, [_len, 10].min
    top_index = 10 * cur_page
    bot_index = [10 * (cur_page + 1), _len].min
    while _selected == -1
      puts SPLIT_LINE
      puts @head_message
      puts "#{SPLIT_LINE}List #{top_index+1}~#{bot_index} of #{_len}\n#{SPLIT_LINE.chomp}" if @list.size > 10
      cnt = 0
      accepted_input = []
      @list[top_index...bot_index].each do |item|
        puts "[#{cnt}] #{item.message}"
        accepted_input << cnt.to_s
        cnt += 1
      end
      accepted_input << 'Q' if @quit_action.respond_to?(:call)
      accepted_input << 'A' if cur_page > 0
      accepted_input << 'D' if bot_index < _len
      puts "#{SPLIT_LINE}#{@tail_message}" if @tail_message.length > 0
      puts "#{SPLIT_LINE}#{'Q: quit' if @quit_action}#{' A: prev page' if cur_page > 0}#{' D: next page' if bot_index < _len}"
      print ">> "
      _in = ''
      _in = STDIN.getch.upcase until accepted_input.include?(_in)
      puts _in
      case _in
      when 'A'; cur_page -= 1;
      when 'D'; cur_page += 1;
      when 'Q'; return @quit_action.call;
      when /\d+/; _selected = _in.to_i + cur_page * 10;
      end
    end # while not selected
    return @list[_selected].action.call if @list[_selected].action.respond_to? :call
    return _selected
  end
end