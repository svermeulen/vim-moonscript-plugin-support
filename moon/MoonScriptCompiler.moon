
local Path

Vim =
  echo: (message) ->
    vim.api.nvim_out_write(message .. '\n')

  echoError: (message) ->
    vim.api.nvim_err_writeln(message)

  callFunction: (functionName, args) ->
    vim.api.nvim_call_function(functionName, args)

Assert = (condition, message) ->
  if not condition
    if message
      error("Assert hit! " .. message)
    else
      error("Assert hit!")

Path =
  join: (left, right) ->
    result = left
    lastChar = left\sub(-1)

    if lastChar != '/' and lastChar != '\\'
      result ..= '/'

    result ..= right
    return result

  normalize: (path) ->
    result = string.gsub(path, "\\", "/")

    if result\sub(-1) == '/'
      result = result\sub(0, #result - 1)

    return result

  makeMissingDirectoriesInPath: (path) ->
    dirPath = Path.getDirectory(path)
    Vim.callFunction('mkdir', { dirPath, 'p' })

  getDirectory: (path) ->
    return path\match('^(.*)[\\/][^\\/]*$')

File =
  exists: (path) ->
    return Vim.callFunction('filereadable', { path }) != 0

  getModificationTime: (path) ->
    return Vim.callFunction('getftime', { path })

  delete: (path) ->
    Vim.callFunction('delete', { path })

Directory =
  getAllFilesWithExtensionRecursive: (path, extension) ->
    return [Path.normalize(x) for x in *Vim.callFunction('globpath', {path, "**/*.#{extension}", 0, 1})]

tableContains = (table, element) ->
  for value in *table
    if value == element then
      return true

  return false

deleteOrphanedLuaFiles = (validBaseNames, pluginRoot, verbose) ->
  luaDir = Path.join(pluginRoot, 'lua')

  for filePath in *Directory.getAllFilesWithExtensionRecursive(luaDir, 'lua')
    baseName = filePath\sub(#luaDir + 2)
    baseName = baseName\sub(0, #baseName - 4)

    if not tableContains(validBaseNames, baseName)
      File.delete(filePath)
      if verbose
        vim.api.nvim_command("echo 'Deleted file #{filePath} since it had no matching moon file'")

timeStampIsGreater = (file1Path, file2Path) ->
    time1 = File.getModificationTime(file1Path)
    time2 = File.getModificationTime(file2Path)

    return time1 > time2

local MoonScriptCompiler
MoonScriptCompiler =
  -- Returns true if it was compiled
  compileMoonIfOutOfDate: (moonPath, luaPath) ->

    if not File.exists(luaPath) or timeStampIsGreater(moonPath, luaPath)
      Path.makeMissingDirectoriesInPath(luaPath)
      output = Vim.callFunction("system", { "moonc -o \"#{luaPath}\" -n \"#{moonPath}\"" })

      if vim.api.nvim_eval('v:shell_error') != 0
        Vim.echoError("Errors occurred while compiling file '#{moonPath}'")
        Vim.echoError(output)
        -- Can we safely print the output here?
        return false

      return true

    return false

  compileAll: (verbose) ->
    rtp = vim.api.nvim_eval('&rtp')
    paths = [Path.normalize(x) for x in string.gmatch(rtp, "([^,]+)")]

    numUpdated = 0

    for pluginRoot in *paths
      moonBaseNames = {}
      moonDir = Path.join(pluginRoot, 'moon')

      for filePath in *Directory.getAllFilesWithExtensionRecursive(moonDir, 'moon')
        baseName = filePath\sub(#moonDir + 2)
        baseName = baseName\sub(0, #baseName - 5)
        table.insert(moonBaseNames, baseName)

      if #moonBaseNames > 0
        deleteOrphanedLuaFiles(moonBaseNames, pluginRoot, verbose)

        luaDir = Path.join(pluginRoot, 'lua')

        for baseName in *moonBaseNames
          luaPath = Path.join(luaDir, baseName) .. '.lua'
          moonPath = Path.join(moonDir, baseName) .. '.moon'

          if MoonScriptCompiler.compileMoonIfOutOfDate(moonPath, luaPath)
            if verbose
              vim.api.nvim_command("echo 'Compiled file #{moonPath}'")

            -- Also delete it from the package cache so the next time require(baseName)
            -- is called, it will load the new file
            packageName = baseName\gsub("\\", ".")\gsub("/", ".")
            package.loaded[packageName] = nil
            numUpdated += 1

    if verbose and numUpdated == 0
      vim.api.nvim_command("echo 'All moon files are already up to date'")

    return numUpdated

return MoonScriptCompiler
