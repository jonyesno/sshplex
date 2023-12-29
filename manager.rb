require 'parallel'

class Manager
  attr_accessor :hosts

  def initialize(hosts, **kwargs)
    @hosts  = hosts
    hostlen = hosts.map(&:length).max

    @filter = Regexp.new('.')
    self.set_filter(kwargs[:filter]) unless kwargs[:filter].empty?

    @alias  = kwargs[:alias]
    @logger = kwargs[:cli_logger]

    @plex = hosts.map { |h| Plex.new(h,
                                     agent:  kwargs[:agent],
                                     logger: kwargs[:plex_logger],
                                     mode:   kwargs[:mode],
                                     out:    kwargs[:out].call(h.rjust(hostlen)),
                                     user:   kwargs[:user]) }
  end

  def connect
    Parallel.map(@plex
      .select { |p| @filter.match(p.hostname) }
      .reject { |p| p.connected? }, in_threads: 12) { |p|
      @logger.info("connecting to #{p.hostname}")
      p.open
      @logger.info("connected  to #{p.hostname}")
    }
  end

  def set_filter(regexps)
    @filter = Regexp.union(regexps)
  end

  def process
    self.connect

    timestamp = Time.now

    active = @plex
      .select { |p| p.connected? && !p.eof? }
      .select { |p| @filter.match(p.hostname) }

    pending = active.dup

    Signal.trap("INT") { pending.map { |p| p.etx! } }

    while pending.length > 0
      if Time.now - timestamp > 10
        done = active.select { |p| p.eof? || p.idle? }.map(&:hostname)
        wait = active.map(&:hostname) - done
        @logger.info("done: #{done.join(',')}")
        @logger.info("wait: #{wait.join(',')}")
        timestamp = Time.now
      end

      p = pending.shift

      p.process

      next if p.eof?
      next if p.idle?

      pending.push(p)
    end

    Signal.trap("INT", "DEFAULT")

    if @plex.all? { |p| p.eof? }
      @logger.info("all done")
      raise RuntimeError, "FIXME: handle all shell eof"
    end
  end

  def prompt
    cmd = Readline.readline("sshplex% ", true)
    return if cmd.nil?
    return if cmd.empty?

    if ctrl_cmd = cmd[/^:(\w+)/, 1]
      case ctrl_cmd
      when 'on'
        if patterns = cmd[/^:on (.*)$/, 1]
          set_filter(patterns.split)
          return
        else
          @logger.info("didn't update host filter")
        end
      else
        if new_cmd = @alias[ctrl_cmd]
          Readline.pre_input_hook = -> {
            Readline.insert_text(new_cmd)
            Readline.redisplay
            Readline.pre_input_hook = nil
          }
          return
        else
          @logger.info("didn't expand alias #{ctrl_cmd}")
        end
      end
    end

    Readline::HISTORY.push cmd

    @plex
      .filter { |p| @filter.match(p.hostname) }
      .each { |p| p.send(cmd) }
  end
end
