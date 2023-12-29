require 'net/ssh'

class Plex
  attr_reader :hostname

  # https://stackoverflow.com/a/29497680
  ANSI_ESCAPE_CODES = Regexp.new('[\u001b\u009b][\[();?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]')

  CONNECTION_ERRORS = [ SocketError, Errno::ECONNREFUSED ]

  def initialize(hostname, **kwargs)
    @hostname = hostname

    @agent  = kwargs[:agent]  || false
    @logger = kwargs[:logger] || Logger.new
    @mode   = kwargs[:mode]   || :exec
    @out    = kwargs[:out]    || STDOUT
    @user   = kwargs[:user]   # when nil ~/.ssh/config is used

    @buffer = []

    @idle = false
    @eof  = false

    @prompt = Regexp.new('(^% | \d+ # | \d+ \$ )$') # ymmv
  end

  def open
    begin
      @ssh = Net::SSH.start(@hostname,
                            @user,
                            forward_agent: @agent,
                            logger: @logger)

    rescue *CONNECTION_ERRORS => e
      @logger.error("can't connect to #{@hostname}: #{e}")
      @ssh = nil
    end

    case @mode
    when :exec
      @idle = true  # exec channel is opened every time, so consider it idle at start
    when :shell
      @idle = false # process shell channel setup before accepting commands
      self.shell
    end
  end

  def shell
    return unless @ssh

    @shell = @ssh.open_channel do |channel|
      @logger.info("opened shell channel to #{@hostname}")

      channel.request_pty do |ch, success|
        raise RuntimeError, "pty failed" unless success
      end

      channel.send_channel_request("shell") do |ch, success|
        raise RuntimeError, "shell failed" unless success

        ch.on_data do |ch, data|
          @buffer << data
        end

        ch.on_extended_data do |ch, type, data|
          @buffer << data
        end

        ch.on_request("exit-status") do |ch, data|
          code = data.read_long
          @buffer << "# exit: #{code}\n"
          @eof = true
        end

        ch.on_request("exit-signal") do |ch, data|
          signal = data.read_long
          @buffer << "# signal: #{signal}\n"
          @eof = true
        end
      end
    end
  end

  def exec(cmd)
    return unless @ssh

    @exec = @ssh.open_channel do |channel|
      @logger.info("opened exec channel to #{@hostname}")

      channel.request_pty do |ch, success|
        raise RuntimeError, "pty failed" unless success
      end

      channel.exec(cmd) do |ch, success|
        raise RuntimeError, "exec failed" unless success

        ch.on_data do |ch, data|
          @buffer << data
        end

        ch.on_extended_data do |ch, type, data|
          @buffer << data
        end

        ch.on_request("exit-status") do |ch, data|
          code = data.read_long
          @buffer << "# exit: #{code}\n"
          @idle = true
        end

        ch.on_request("exit-signal") do |ch, data|
          signal = data.read_long
          @buffer << "# signal: #{signal}\n"
          @idle = true
        end
      end
    end
  end

  def process
    @ssh.process(0.1)
    unless @buffer.empty?

      # join buffer lines, strip out ANSI chaos
      clean = @buffer.join.gsub(ANSI_ESCAPE_CODES, '').gsub("\r", "")

      # emit all the \n terminated lines, keep the current in-progress line
      lines   = clean.split(/\n/, -1)
      current = lines.pop
      emit    = lines.join("\n")

      unless emit.empty?
        @out.puts emit
      end

      if current.empty?
        @buffer = [] # avoid a buffer of just ""
      else
        @buffer = [ current ]
      end

      if current.match(@prompt)
        @idle = true
        @out.puts current.gsub(@prompt, '')

        @buffer = []
      end
    end
  end

  def send(data)
    return if @eof

    @idle = false

    case @mode
    when :shell
      @buffer = [ 'sshplex% ' ]         # add synthetic prompt to output
      @shell.send_data(data + "\n")
    when :exec
      @buffer = [ "# exec: #{data}\n" ] # record command in output
      self.exec(data)
    end
  end

  def etx!
    return if @eof

    case @mode
    when :shell
      @shell.send_data("\x03")
    when :exec
      @exec.send_data("\x03")
    end
  end

  def connected?
    !@ssh.nil?
  end

  def eof?
    @eof
  end

  def idle?
    @idle
  end

end
