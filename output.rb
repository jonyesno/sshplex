class Output
  def initialize(prefix = "", io = STDOUT)
    @io     = io
    @prefix = prefix

    @io.sync = true
  end

  def puts(data)
    @io.puts(data.split("\n").map { |l| "#{@prefix} #{l}" }.join("\n"))
  end

  def print(data)
    @io.print(data.split("\n").map { |l| "#{@prefix} #{l}" }.join("\n"))
  end

  def self.cleanup
    return unless ENV['TMUX']

    %x[ tmux select-pane -T sshplex ]
    tmux_window = %x[ tmux display-message -p '#W' ].chomp
    tmux_panes  = %x[ tmux list-panes -t #{tmux_window} -F '#T #P' ]
      .split(/\n/)
      .map(&:split)
      .to_h

    if tmux_panes.keys.include?("log")
      %x[ tmux kill-pane -t #{tmux_panes['log']} ]
    end

  end

  def self.stdout
    -> (h) { Output.new(h, STDOUT) }
  end

  def self.tmux
    raise RuntimeError, "no tmux session" unless ENV['TMUX']

    self.cleanup

    pipe = IO.popen("tmux split-pane -v -l 80% -b -I", "w+")
    %x[ tmux select-pane -T log ]
    %x[ tmux select-pane -l ]

    out = -> (h) { Output.new(h, pipe) }
  end

end
