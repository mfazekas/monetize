# encoding: utf-8

require 'money'
require 'monetize/core_extensions'
require 'monetize/version'
require 'collection'

module Monetize

  CURRENCY_SYMBOLS = {
    '$'    => 'USD',
    '€'    => 'EUR',
    '£'    => 'GBP',
    '₤'    => 'GBP',
    'R$'   => 'BRL',
    'R'    => 'ZAR',
    '¥'    => 'JPY',
    'C$'   => 'CAD'
  }

  MULTIPLIER_SUFFIXES = {
    'K'    => 3,
    'M'    => 6,
    'B'    => 9,
    'T'    => 12
  }
  MULTIPLIER_SUFFIXES.default = 0
  MULTIPLIER_REGEXP = Regexp.new('\d(%s)\b[^\d]*$' % MULTIPLIER_SUFFIXES.keys.join('|'), 'i')

  # Class methods
  class << self
    # @attr_accessor [true, false] assume_from_symbol Use this to enable the
    #   ability to assume the currency from a passed symbol
    attr_accessor :assume_from_symbol
  end

  def self.parse(input, currency = Money.default_currency, options = {})
    input = input.to_s.strip

    computed_currency = if options.fetch(:assume_from_symbol) { assume_from_symbol }
                          compute_currency(input)
                        else
                          input[/[A-Z]{2,3}/]
                        end

    currency = computed_currency || currency || Money.default_currency
    currency = Money::Currency.wrap(currency)

    fractional = extract_cents(input, currency)
    Money.new(fractional, currency)
  end

  def self.parse_collection(input, currency = Money.default_currency, options = {})
    Collection.parse(input, currency, options)
  end

  def self.from_string(value, currency = Money.default_currency)
    value = BigDecimal.new(value.to_s)
    from_bigdecimal(value, currency)
  end

  def self.from_fixnum(value, currency = Money.default_currency)
    currency = Money::Currency.wrap(currency)
    value = value * currency.subunit_to_unit
    Money.new(value, currency)
  end

  def self.from_float(value, currency = Money.default_currency)
    value = BigDecimal.new(value.to_s)
    from_bigdecimal(value, currency)
  end

  def self.from_bigdecimal(value, currency = Money.default_currency)
    currency = Money::Currency.wrap(currency)
    value = value * currency.subunit_to_unit
    value = value.round unless Money.infinite_precision
    Money.new(value, currency)
  end

  def self.from_numeric(value, currency = Money.default_currency)
    case value
    when Fixnum
      from_fixnum(value, currency)
    when Numeric
      value = BigDecimal.new(value.to_s)
      from_bigdecimal(value, currency)
    else
      raise ArgumentError, "'value' should be a type of Numeric"
    end
  end

  def self.extract_cents(input, currency = Money.default_currency)
    multiplier_suffix = (matches = MULTIPLIER_REGEXP.match(input)) ? matches[1].upcase : nil
    multiplier_exp = MULTIPLIER_SUFFIXES[multiplier_suffix]

    num = input.gsub(/[^\d.,'-]/, '')

    negative = num =~ /^-|-$/ ? true : false

    decimal_char = currency.decimal_mark

    num = num.sub(/^-|-$/, '') if negative

    if num.include?('-')
      raise ArgumentError, 'Invalid currency amount (hyphen)'
    end

    num.chop! if num.match(/[\.|,]$/)

    used_delimiters = num.scan(/[^\d]/)

    case used_delimiters.uniq.length
    when 0
      major = num
      minor = 0
    when 2
      thousands_separator, decimal_mark = used_delimiters.uniq

      major, minor = num.gsub(thousands_separator, '').split(decimal_mark)
      min = 0 unless min
    when 1
      decimal_mark = used_delimiters.first

      if decimal_char == decimal_mark
        major, minor = num.split(decimal_char)
      else
        if num.scan(decimal_mark).length > 1 # multiple matches; treat as decimal_mark
          major = num.gsub(decimal_mark, '')
          minor = 0
        else
          possible_major, possible_minor = num.split(decimal_mark)
          possible_major ||= '0'
          possible_minor ||= '00'

          if possible_minor.length != 3 # thousands_separator
            major = possible_major
            minor = possible_minor
          else
            if possible_major.length > 3
              major = possible_major
              minor = possible_minor
            else
              if decimal_mark == '.'
                major = possible_major
                minor = possible_minor
              else
                major = "#{possible_major}#{possible_minor}"
                minor = 0
              end
            end
          end
        end
      end
    else
      raise ArgumentError, 'Invalid currency amount'
    end

    cents = major.to_i * currency.subunit_to_unit

    cents *= (10**multiplier_exp)
    minor = minor.to_s + ('0' * multiplier_exp)
    shift = minor[0...multiplier_exp].to_i * 100
    cents += shift
    minor = (minor[multiplier_exp..-1] || '')
    minor = if Money.infinite_precision
              (BigDecimal.new(minor) / (10**minor.size)) * currency.subunit_to_unit
            elsif minor.size < currency.decimal_places
              (minor + ('0' * currency.decimal_places))[0, currency.decimal_places].to_i
            elsif minor.size > currency.decimal_places
              if minor[currency.decimal_places, 1].to_i >= 5
                minor[0, currency.decimal_places].to_i + 1
              else
                minor[0, currency.decimal_places].to_i
              end
            else
              minor.to_i
            end

    cents += minor

    negative ? cents * -1 : cents
  end

  private

  def self.contains_currency_symbol?(amount)
    currency_symbol_regex === amount
  end

  def self.compute_currency(amount)
    if contains_currency_symbol?(amount)
      matches = amount.match(currency_symbol_regex)
      CURRENCY_SYMBOLS[matches[:symbol]]
    else
      amount[/[A-Z]{2,3}/]
    end
  end

  def self.regex_safe_symbols
    CURRENCY_SYMBOLS.keys.map { |key|
      Regexp.escape(key)
    }.join('|')
  end

  def self.currency_symbol_regex
    /\A[\+|\-]?(?<symbol>#{regex_safe_symbols})/
  end
end
