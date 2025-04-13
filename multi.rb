require 'net/ssh/multi'

class Multi
  attr_accessor :hosts

  # https://stackoverflow.com/a/29497680
  ANSI_ESCAPE_CODES = Regexp.new('[\u001b\u009b][\[();?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]')

  CONNECTION_ERRORS = [
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Net::SSH::Disconnect,
    SocketError,
  ]

  def initialize(hosts, **kwargs)
    @hosts  = hosts
    hostlen = hosts.map(&:length).max

    @filter = Regexp.new('.')
    self.set_filter(kwargs[:filter]) unless kwargs[:filter].empty?

    @alias  = kwargs[:alias]
    @logger = kwargs[:multi_logger]
    @mode   = kwargs[:mode]

    @multi = Net::SSH::Multi.start

    @buffer = Hash.new { |h,k| h[k] = [] }
    @out = @hosts.map { |h| [h, kwargs[:out].call(h) ] }.to_h
  end

  def configure
    @hosts.select { |p| @filter.match(p) }
      .tap { |h| @logger.info("adding host #{h}") }
      .map do |h|
        begin
          @multi.use(h, forward_agent: true, logger: @logger)
        rescue *CONNECTION_ERRORS => e
          @logger.error("can't connect to #{@hostname}: #{e}")
        end
      end
    @logger.info("configured")
  end

  def set_filter(regexps)
    @filter = Regexp.union(regexps)
  end

  def prompt
    cmd = nil
    loop do
      cmd = Readline.readline("sshplex% ", true)
      case
      when cmd.nil?
        next
      when cmd.empty?
        next
      when new_cmd = @alias[cmd.split.first]
        Readline.pre_input_hook = -> {
          Readline.insert_text(new_cmd)
          Readline.redisplay
          Readline.pre_input_hook = nil
        }
        next
      end

      break
    end
    Readline::HISTORY.push cmd
    cmd
  end

  def exec(cmd)

    multi_channel = @multi.open_channel do |channel|
      channel.request_pty do |ch, success|
        raise "pty failed" unless success
      end

      channel.exec(cmd) do |ch, success|
        raise "exec failed" unless success

        channel.on_data do |ch, data|
          @buffer[ch[:host]] << data
        end

        channel.on_extended_data do |ch, data|
          @buffer[ch[:host]] << data
        end

        channel.on_request("exit-status") do |ch, data|
          code = data.read_long
          @buffer[ch[:host]] << "# exit: #{code}\n"
        end
      end
    end

    Thread.new { @multi.loop }

    while multi_channel.active?
      sleep(0.2)
      emit_buffers(multi_channel.channels)
    end
    @logger.info("final")
    emit_buffers(multi_channel.channels)
  end

  def emit_buffers(channels)
    channels.select { |c| !c.active? }.each do |ch|
      next if @buffer[ch[:host]].empty?

      # join buffer lines, strip out ANSI chaos
      clean = @buffer[ch[:host]].join.gsub(ANSI_ESCAPE_CODES, '').gsub("\r", "")

      # emit all the \n terminated lines, keep the current in-progress line
      lines   = clean.split(/\n/, -1)
      current = lines.pop
      emit    = lines.join("\n")

      unless emit.empty?
        @out[ch[:host]].puts emit
      end

      # don't emit this buffer again
      @buffer[ch[:host]] = []
    end
  end
end
