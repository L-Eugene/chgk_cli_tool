#!/usr/bin/env ruby
require 'date'
require 'optparse'
require 'rating_chgk_v2'
require 'yaml'

CONFIG_FILE = 'config.yml'

options = {
    date: Date.today.to_s,
    difficulty_min: 0,
    difficulty_max: 10,
    type: [], # Possible values are: "Синхрон", "Асинхрон", "Онлайн", etc.
    skip: []
}

cli_options = {}

if File.exist?(CONFIG_FILE)
    options.merge!(YAML.load_file(CONFIG_FILE, symbolize_names: true))
end

client = RatingChgkV2.client

OptionParser.new do |opts|
    opts.banner = "Usage: find.rb [options]"

    opts.on("-d", "--date DATE", "Date to search for") do |v|
        unless v.match?(/\d{4}-\d{2}-\d{2}/)
            puts "Invalid date format"
            exit
        end

        cli_options[:date] = v
    end

    opts.on("-l", "--level LEVEL", "Minimal difficulty level") do |v|
        unless v.match?(/\d+(\.\d+)?/)
            puts "Invalid difficulty format"
            exit
        end

        cli_options[:difficulty_min] = v.to_f
    end

    opts.on("-L", "--level-max LEVEL", "Maximal difficulty level") do |v|
        unless v.match?(/\d+(\.\d+)?/)
            puts "Invalid difficulty format"
            exit
        end

        cli_options[:difficulty_max] = v.to_f
    end

    opts.on("-f", "--file FILE", "Load options from config file") do |v|
        cli_options[:file] = v
    end

    opts.on("-F", "--file_dump FILE", "Dump options to config file") do |v|
        cli_options[:file_dump] = v
    end

    opts.on("-s", "--skip VENUE", "Skip tournaments already played or scheduled on given venue") do |v|
        unless v.match?(/\d+/)
            puts "Invalid venue format (must be integer)"
            exit
        end

        cli_options[:skip] ||= []
        cli_options[:skip] << v
    end

    opts.on("-t", "--type TYPE", "Tournament type") do |v|
        types = client.tournament_types.map(&:name)
        unless types.any?(v)
            puts "Invalid tournament type"
            puts "Possible values are: #{types.join(', ')}"
            exit
        end

        cli_options[:type] ||= []
        cli_options[:type] << v
    end
end.parse!

options.merge!(cli_options)

if options[:file] && File.exist?(options[:file])
    options.merge!(YAML.load_file(options[:file], symbolize_names: true))
end

if options[:file_dump]
    File.write(options[:file_dump], options.to_yaml)
end

list = client.tournaments(
    'dateStart[before]': options[:date],
    'dateEnd[after]': options[:date],
    itemsPerPage: 1000
).select do |t|
    # Select only tournaments with given type (or all if type is not specified)
    options[:type].empty? || options[:type].any?(t.type["name"])
end.select do |t| 
    # Select only tournaments with difficulty level unknow or in given range
    t.difficultyForecast.nil? || t.difficultyForecast.between?(options[:difficulty_min], options[:difficulty_max])
end.select do |t|
    # Skip tournaments already played or scheduled on given venues
    next true if options[:skip].empty?

    client.tournament(t.id).requests.none? do |request|
        # C stands for Cancelled, D stands for Declined
        %w(C D).none?(request.status) && options[:skip].any?(request.venue["id"].to_s)
    end
end

typel = list.map { |obj| obj.type["name"].size }.max
list.each do |obj|
    puts "#{obj.type["name"].rjust(typel)} #{(obj.difficultyForecast || '?').to_s.rjust(5) } #{obj.name} (https://rating.chgk.info/tournament/#{obj.id})"
end
