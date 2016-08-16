require 'Tempfile'
require 'json'

def make_gif(path_to_video)
  @path_to_video = path_to_video
  get_show_info

  extract_subtitle_track

  FileUtils.mkdir_p "#{@show_name}/#{@episode}/gifs/uncaptioned"
  FileUtils.mkdir_p "#{@show_name}/#{@episode}/gifs/captioned"
  FileUtils.mkdir_p "#{@show_name}/#{@episode}/gifs/optimized"

  @parsed_subs = split_subs

  @parsed_subs.each do |sub|
    set_show_info(sub)
    generate_gif(sub)
  end

  find_incomplete_sentences
  dump_json
end

def get_show_info
  puts "Show name?"
  @show_name = gets.chomp
  puts "Season & Episode? Example format: S01E01, E04, or nil for n/a"
  @episode = gets.chomp
end

def extract_subtitle_track
  track_number = find_subtitle_track
  system('mkvextract', 'tracks', @path_to_video, "#{track_number}:#{@show_name}_#{@episode}_subtitles.srt")
end

def find_subtitle_track
  tracks = `mkvinfo #{@path_to_video}`
  subtitles_info = tracks.split("A track").delete_if {|track| !track.include?("subtitles") }
  match = /(track ID for mkvmerge & mkvextract:)(.\d+)+/.match(subtitles_info.to_s)

  match[2].lstrip
end

def split_subs
  subtitles = File.read("./#{@show_name}_#{@episode}_subtitles.srt")

  grouped, splitted = [], []

  subtitles.split("\n").push("\n").each do |sub|
    if sub.strip.empty?

      start_time, end_time  = parse_times(grouped[1])

      splitted.push({
        sub_id: grouped[0],
        start_time: start_time.sub(",","."),
        end_time: end_time,
        duration: calculate_duration(start_time, end_time),
        content: grouped[2..-1].join("\n")
      })
      grouped = []
    else
      grouped.push sub.strip
    end
  end
  system("rm", "./#{@show_name}_#{@episode}_subtitles.srt")
  splitted
end

def set_show_info(sub)
  sub[:show] = @show_name.delete(' ')
  sub[:episode] = @episode.delete(' ')
end

def parse_times(time_range)
  start_time, end_time = time_range.split(' --> ').each { |x| x.sub(',', '.') }
  return start_time, end_time
end

def calculate_duration(start_time, end_time)
  beginning = convert_to_time(start_time)
  ending = convert_to_time(end_time)
  milliseconds =  ending - beginning
  return milliseconds
end

def convert_to_time(time)
  match = time.match(/(?<h>\d+):(?<m>\d+):(?<s>\d+)[,.](?<ms>\d+)/)
  Time.utc(1969, 12, 31, match[1], match[2], match[3], match[4]).to_f
end

def generate_gif(sub)
  Tempfile.create(%w[palette .png]) { |f|
    puts f.path

    system("ffmpeg", "-v", "warning", "-ss", sub[:start_time], "-t", sub[:duration].to_s, "-i", @path_to_video, "-vf", "fps=20,scale=320:-1:flags=lanczos,palettegen", "-y", f.path)
    system("ffmpeg", "-v", "warning", "-ss", sub[:start_time], "-t", sub[:duration].to_s, "-i", @path_to_video, "-i", f.path, "-lavfi", "fps=20,scale=320:-1:flags=lanczos [x]; [x][1:v] paletteuse", "-y", "./#{@show_name}/#{@episode}/gifs/uncaptioned/#{sub[:show]}_#{sub[:episode]}_#{sub[:sub_id]}.gif")
    annotate(sub)
  }
end

def annotate(sub)
  system('convert', "./#{@show_name}/#{@episode}/gifs/uncaptioned/#{sub[:show]}_#{sub[:episode]}_#{sub[:sub_id]}.gif", "-gravity", "south", "-font", "Helvetica", "-pointsize", "14", "-stroke", '#000C', "-strokewidth", "3", "-annotate", "0", "#{sub[:content]}\n", "-stroke", "none", "-fill", "white", "-annotate", "0", "#{sub[:content]}\n", "./#{@show_name}/#{@episode}/gifs/captioned/#{sub[:show]}_#{sub[:episode]}_#{sub[:sub_id]}.gif")

  optimize_gif(sub)
  cleanup_gifs(sub)
end

def cleanup_gifs(sub)
  system("rm", "./#{@show_name}/#{@episode}/gifs/uncaptioned/#{sub[:show]}_#{sub[:episode]}_#{sub[:sub_id]}.gif")
  system("rm", "./#{@show_name}/#{@episode}/gifs/captioned/#{sub[:show]}_#{sub[:episode]}_#{sub[:sub_id]}.gif")
end

def optimize_gif(sub)
  system("gifsicle", "-O3", "./#{@show_name}/#{@episode}/gifs/captioned/#{sub[:show]}_#{sub[:episode]}_#{sub[:sub_id]}.gif", "-o", "./#{@show_name}/#{@episode}/gifs/optimized/#{sub[:show]}_#{sub[:episode]}_#{sub[:sub_id]}.gif", "--colors", "256")
end

def merge_gif(sub1, sub2)
  if sub2.nil?
    puts "Nothing to merge with. Moving on."
  else
    system("gifsicle", "--crop", "320x180", "--colors", "256", "--merge", "./#{@show_name}/#{@episode}/gifs/optimized/#{sub1[:show]}_#{sub1[:episode]}_#{sub1[:sub_id]}.gif", "./#{@show_name}/#{@episode}/gifs/optimized/#{sub2[:show]}_#{sub2[:episode]}_#{sub2[:sub_id]}.gif", "-o", "./#{@show_name}/#{@episode}/gifs/optimized/#{sub1[:show]}_#{sub1[:episode]}_#{sub1[:sub_id]}.gif")
    system("rm", "./#{@show_name}/#{@episode}/gifs/optimized/#{sub2[:show]}_#{sub2[:episode]}_#{sub2[:sub_id]}.gif")
    sub1[:content] + ' ' + sub2[:content]
    @parsed_subs.delete(sub2)
  end
end

def find_incomplete_sentences
  @parsed_subs.each do |sub|
    if sub[:content].match(/(?:\.|\?|\!)(?= [^a-z]|$)/).nil?
      next_sub = sub[:sub_id].to_i
      puts "Merging incomplete sentences in gifs: #{sub[:sub_id]} & #{next_sub + 1}"
      merge_gif(sub, @parsed_subs[next_sub])
    end
  end
end

def dump_json
  File.open("#{@show_name}/#{@episode}/gifs.json","w") do |f|
    @parsed_subs.each do |sub|
      sub[:filename] = sub[:show] + '_' + sub[:episode] + '_' + sub[:sub_id] + '.gif'
      sub[:show] = @show_name
      sub[:episode] = @episode
      f.write('{"index":{"_index":"index", "_type":"subtitles"}' + "\n")
      f.write(sub.to_json + "\n")
    end
  end
end

