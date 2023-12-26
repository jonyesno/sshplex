class Output
  def initialize(prefix = "", io = STDOUT)
    @io = io
    @prefix = prefix
    @io.sync = true
  end

  def puts(data)
    @io.puts(data.split("\n").map { |l| "#{@prefix} #{l}" }.join("\n"))
  end

  def print(data)
    @io.print(data.split("\n").map { |l| "#{@prefix} #{l}" }.join("\n"))
  end
end

