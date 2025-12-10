local M = {}

-- Utility: Detect language from file extension and requirement content
function M.detect_language(context_path, requirement_content)
  local ext = context_path:match("^.+(%..+)$")
  if ext then
    if ext == ".py" then return "python"
    elseif ext == ".rb" then return "ruby"
    elseif ext == ".ex" or ext == ".exs" then return "elixir"
    elseif ext == ".tf" then return "terraform"
    elseif ext == ".java" then return "java"
    elseif ext == ".yaml" or ext == ".yml" then return "kubernetes"
    end
  end
  -- Fallback: Infer from requirement content
  if requirement_content:lower():find("python") then return "python" end
  if requirement_content:lower():find("ruby") then return "ruby" end
  if requirement_content:lower():find("elixir") then return "elixir" end
  if requirement_content:lower():find("terraform") then return "terraform" end
  if requirement_content:lower():find("kubernetes") then return "kubernetes" end
  if requirement_content:lower():find("java") then return "java" end
  return "general"
end

-- Utility: Extract tasks from requirement content
function M.extract_tasks(requirement_content)
  local tasks = {}
  local priority = 1
  for line in requirement_content:gmatch("[^\r\n]+") do
    if line:match("^%-") or line:match("^%*") then
      local section = "Functional"
      if line:lower():find("non%-functional") then section = "NonFunctional" end
      table.insert(tasks, {section = section, priority = "P" .. priority, text = line:gsub("^%- ", ""):gsub("^%* ", "")})
      priority = priority + 1
    end
  end
  return tasks
end

-- Utility: Add best practice tasks by language
function M.best_practice_tasks(language)
  local bp = {}
  if language == "python" then
    table.insert(bp, {section = "BestPractice", priority = "P2", text = "Add unit tests for all new functions"})
    table.insert(bp, {section = "BestPractice", priority = "P3", text = "Document public methods with docstrings"})
  elseif language == "ruby" then
    table.insert(bp, {section = "BestPractice", priority = "P2", text = "Add RSpec tests for new features"})
    table.insert(bp, {section = "BestPractice", priority = "P3", text = "Ensure code follows RuboCop guidelines"})
  elseif language == "elixir" then
    table.insert(bp, {section = "BestPractice", priority = "P2", text = "Write ExUnit tests for modules"})
    table.insert(bp, {section = "BestPractice", priority = "P3", text = "Add module documentation"})
  elseif language == "terraform" then
    table.insert(bp, {section = "BestPractice", priority = "P2", text = "Validate Terraform plan before applying"})
    table.insert(bp, {section = "BestPractice", priority = "P3", text = "Document resources and variables"})
  elseif language == "kubernetes" then
    table.insert(bp, {section = "BestPractice", priority = "P2", text = "Validate manifests with kubeval"})
    table.insert(bp, {section = "BestPractice", priority = "P3", text = "Add resource requests and limits"})
  elseif language == "java" then
    table.insert(bp, {section = "BestPractice", priority = "P2", text = "Add JUnit tests for new classes"})
    table.insert(bp, {section = "BestPractice", priority = "P3", text = "Document classes with Javadoc"})
  else
    table.insert(bp, {section = "BestPractice", priority = "P2", text = "Add tests for new functionality"})
    table.insert(bp, {section = "BestPractice", priority = "P3", text = "Document code changes"})
  end
  return bp
end

return M
