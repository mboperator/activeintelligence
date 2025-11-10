class ReadmeWriterTool < ActiveIntelligence::Tool
  name "write_readme"
  description "Write a README.md file to the specified directory with the provided content"

  param :directory, type: String, required: true,
        description: "Directory where README.md should be written"
  param :content, type: String, required: true,
        description: "Markdown content for the README.md file"
  param :backup_existing, type: String, required: false, default: "true",
        enum: ["true", "false"],
        description: "Create backup of existing README.md if it exists"

  def execute(params)
    directory = File.expand_path(params[:directory])
    content = params[:content]
    backup_existing = params[:backup_existing] == "true"

    # Validate directory exists
    unless Dir.exist?(directory)
      return error_response("Directory not found: #{directory}")
    end

    readme_path = File.join(directory, 'README.md')
    backup_path = nil

    # Backup existing README if requested
    if backup_existing && File.exist?(readme_path)
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      backup_path = File.join(directory, "README.md.backup_#{timestamp}")
      FileUtils.cp(readme_path, backup_path)
    end

    # Write the README
    File.write(readme_path, content)

    success_response({
      readme_path: readme_path,
      bytes_written: content.bytesize,
      backup_created: !backup_path.nil?,
      backup_path: backup_path
    })
  rescue Errno::EACCES
    error_response("Permission denied writing to: #{readme_path}")
  rescue StandardError => e
    error_response("Failed to write README: #{e.message}", details: { error_class: e.class.to_s })
  end
end
