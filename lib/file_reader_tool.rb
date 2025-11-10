class FileReaderTool < ActiveIntelligence::Tool
  name "read_file"
  description "Read the contents of a file. Use this to examine important files like package.json, setup.py, Gemfile, etc."

  param :file_path, type: String, required: true,
        description: "Path to the file to read"
  param :max_lines, type: Integer, required: false, default: 500,
        description: "Maximum number of lines to read (default: 500)"

  def execute(params)
    file_path = File.expand_path(params[:file_path])
    max_lines = params[:max_lines]

    # Validate file exists
    unless File.exist?(file_path)
      return error_response("File not found: #{file_path}")
    end

    # Validate it's a file
    unless File.file?(file_path)
      return error_response("Path is not a file: #{file_path}")
    end

    # Check file size (limit to 1MB for safety)
    file_size = File.size(file_path)
    if file_size > 1_048_576  # 1MB
      return error_response(
        "File too large to read (#{format_bytes(file_size)}). Maximum 1MB.",
        details: { file_size: file_size }
      )
    end

    # Read file content
    content = File.readlines(file_path).take(max_lines).join
    total_lines = File.foreach(file_path).count
    truncated = total_lines > max_lines

    success_response({
      file_path: file_path,
      content: content,
      total_lines: total_lines,
      lines_read: [total_lines, max_lines].min,
      truncated: truncated,
      size_bytes: file_size
    })
  rescue Errno::EACCES
    error_response("Permission denied reading file: #{file_path}")
  rescue StandardError => e
    error_response("Failed to read file: #{e.message}", details: { error_class: e.class.to_s })
  end

  private

  def format_bytes(bytes)
    units = ['B', 'KB', 'MB', 'GB']
    size = bytes.to_f
    unit_index = 0

    while size >= 1024 && unit_index < units.length - 1
      size /= 1024
      unit_index += 1
    end

    "#{size.round(2)} #{units[unit_index]}"
  end
end
