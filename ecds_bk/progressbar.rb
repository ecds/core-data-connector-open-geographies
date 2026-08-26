# frozen_string_literal: true

class Progressbar
  def initialize(total, description = '')
    @total = total.to_f
    @current = 0
    @description = description.titleize.pluralize
    @start = Time.now
  end

  def increment(steps = 1)
    @current += steps
    percentage = (@current.to_f / @total) * 100
    print("\r\e[0K#{@description} #{@current}/#{@total.to_i} (#{format("%.2f", percentage)}%)")
  end

  def finish
    print("\r\e[0KFinished #{@total.to_i} #{@description} in #{format("%.2f", Time.now - @start)} seconds\n")
  end
end
