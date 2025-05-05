require 'buffer'
require 'net/ssh/multi'

class Multi
  attr_accessor :hosts


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
    @user   = kwargs[:user] || ENV['USER']

    @multi = Net::SSH::Multi.start

    @buffer = Hash.new { |h,k| h[k] = Buffer.new }
    @out = @hosts.map { |h| [h, kwargs[:out].call(h) ] }.to_h

    @prompt = Regexp.new('(^% | \d+ # | \d+ \$ )$') # ymmv
  end

  def configure
    @hosts.select { |p| @filter.match(p) }
      .tap { |h| @logger.info("adding host #{h}") }
      .map do |h|
        begin
          @multi.use(h, forward_agent: true, logger: @logger, user: @user)
        rescue *CONNECTION_ERRORS => e
          @logger.error("can't connect to #{@hostname}: #{e}")
        end
      end
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
      @buffer[channel[:host]].append("# exec: #{cmd}")

      channel.request_pty do |ch, success|
        raise "pty failed" unless success
      end

      channel.exec(cmd) do |ch, success|
        raise "exec failed" unless success

        channel.on_data do |ch, data|
          @buffer[ch[:host]].append(data)
        end

        channel.on_extended_data do |ch, data|
          @buffer[ch[:host]].append(data)
        end

        channel.on_request("exit-status") do |ch, data|
          code = data.read_long
          @buffer[ch[:host]].append("# exit: #{code}\n")
        end
      end
    end

    Thread.new { @multi.loop }

    while multi_channel.active?
      sleep(0.2)
      emit_buffers(multi_channel.channels)
    end
    emit_buffers(multi_channel.channels)
  end

  def open_shell
    @multi_channel = @multi.open_channel do |channel|
      channel[:idle] = false

      channel.request_pty do |ch, success|
        raise "pty failed" unless success
      end

      channel.send_channel_request("shell") do |ch, success|
        raise "shell failed" unless success

        channel.on_data do |ch, data|
          @buffer[ch[:host]].append(data)
          if @buffer[ch[:host]].last_line.match(@prompt)
            ch[:idle] = true
          end
        end

        channel.on_extended_data do |ch, data|
          @buffer[ch[:host]].append(data)
        end

        channel.on_request("exit-status") do |ch, data|
          code = data.read_long
          @buffer[ch[:host]].append("# exit: #{code}\n")
        end

        ch.on_request("exit-signal") do |ch, data|
          signal = data.read_long
          @buffer[ch[:host]].append("signal: #{signal}\n")
        end
      end
    end

    @multi.loop { @multi_channel.channels.any? { |ch| !ch[:idle] } }
    emit_buffers(@multi_channel.channels)
  end

  def send_shell(cmd)
    @multi_channel.channels.each do |ch|
      ch[:idle] = false
      # @buffer[ch[:host]] << "sshplex % "
      @buffer[ch[:host]].ignore(cmd)
      ch.send_data("#{cmd}\n")
    end

    # just @multi.loop { } here breaks agent channels somehow
    Thread.new { @multi.loop { @multi_channel.channels.any? { |ch| !ch[:idle] } } }

    while @multi_channel.channels.any? { |ch| !ch[:idle] }
      sleep(0.2)
      emit_buffers(@multi_channel.channels)
    end
    emit_buffers(@multi_channel.channels)
  end

  def emit_buffers(channels)
    channels.select { |c| !c.active? || c[:idle] }.each do |ch|
      next if @buffer[ch[:host]].empty?

      lines = (@buffer[ch[:host]]).out
      unless lines.empty?
        @out[ch[:host]].puts lines.join("\n")
      end

      @buffer[ch[:host]].empty
    end
  end

end
