require 'find'

class DirectoryScannerTool < ActiveIntelligence::Tool
  name "scan_directory"
  description "Scan a directory and list all files, excluding common ignore patterns like .git, node_modules, etc."

  param :directory, type: String, required: true,
        description: "Path to the directory to scan"
  param :max_depth, type: Integer, required: false, default: 3,
        description: "Maximum depth to traverse (default: 3)"
  param :include_dotfiles, type: String, required: false, default: "false",
        enum: ["true", "false"],
        description: "Whether to include dotfiles in the results"

  # Directories and files to ignore
  IGNORE_PATTERNS = [
    '.git', '.svn', '.hg',
    'node_modules', 'vendor', 'bower_components',
    '.bundle', '.cache', '.pytest_cache', '__pycache__',
    'coverage', '.nyc_output',
    'dist', 'build', 'out', 'target',
    '.DS_Store', 'Thumbs.db',
    '*.log', '*.tmp', '*.swp'
  ].freeze

  def execute(params)
    directory = File.expand_path(params[:directory])
    max_depth = params[:max_depth]
    include_dotfiles = params[:include_dotfiles] == "true"

    # Validate directory exists
    unless Dir.exist?(directory)
      return error_response("Directory not found: #{directory}")
    end

    files = []
    directories = []
    base_depth = directory.count('/')

    Find.find(directory) do |path|
      relative_path = path.sub("#{directory}/", '')
      current_depth = path.count('/') - base_depth

      # Skip if too deep
      if current_depth > max_depth
        Find.prune if File.directory?(path)
        next
      end

      # Skip ignored patterns
      if should_ignore?(path, include_dotfiles)
        Find.prune if File.directory?(path)
        next
      end

      if File.directory?(path) && path != directory
        directories << relative_path
      elsif File.file?(path)
        files << {
          path: relative_path,
          size: File.size(path),
          extension: File.extname(path)
        }
      end
    end

    success_response({
      directory: directory,
      file_count: files.length,
      directory_count: directories.length,
      files: files.sort_by { |f| f[:path] },
      directories: directories.sort
    })
  rescue StandardError => e
    error_response("Failed to scan directory: #{e.message}", details: { error_class: e.class.to_s })
  end

  private

  def should_ignore?(path, include_dotfiles)
    basename = File.basename(path)

    # Ignore dotfiles if not included
    return true if !include_dotfiles && basename.start_with?('.') && basename != '.'

    # Check against ignore patterns
    IGNORE_PATTERNS.any? do |pattern|
      if pattern.include?('*')
        File.fnmatch(pattern, basename)
      else
        basename == pattern || path.include?("/#{pattern}/") || path.end_with?("/#{pattern}")
      end
    end
  end
end
