class Buffer
  # https://stackoverflow.com/a/29497680
  ANSI_ESCAPE_CODES = Regexp.new('[\u001b\u009b][\[();?]*(?:[0-9]{1,4}(?:;[0-9]{0,4})*)?[0-9A-ORZcf-nqry=><]')

  def initialize
    self.empty
  end

  def append(data)
    clean = data
      .gsub(ANSI_ESCAPE_CODES, '')
      .gsub("\r", "")
      .chomp
    return if clean.empty?
    @lines << clean
  end

  def empty
    @lines = []
    @ignore = Set.new
    self.ignore('^%\s*$')         # interline zsh '#'?
    self.ignore('^#.*?\d+s \d+/') # zsh prompt
    self.ignore('\d+ \$')         # bash prompt
  end

  def empty?
    @lines.empty?
  end

  def last_line
    @lines.last
  end

  def ignore(regex)
    @ignore << Regexp.new(regex)
  end

  def out
    @lines.reject { |l| @ignore.detect { |i| l.match(i) } }
  end
end
