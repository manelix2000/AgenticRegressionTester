# IOSAgentDriver CLI - QA Testing Skill Template

This directory contains template files for creating project-specific QA testing skills for LLM agents (Claude, GitHub Copilot, etc.).

**Template Location**:
- **Source**: `agent-cli/skill/` (in repository)
- **Installed**: `~/.agent-cli/skill/` (after installation)

The `skill generate` command reads from `~/.agent-cli/skill/` and creates customized skills in `~/.copilot/skills/{project}-qa-skill/`.

---

## Files

### SKILL.md
The main skill prompt that defines the QA agent's role, capabilities, and testing approach. This file contains:
- **YAML frontmatter** - Skill metadata (name, description, version, tags)
- Professional QA engineer persona
- Systematic testing workflow
- Best practices and patterns
- Example test scenarios
- Troubleshooting guidance

**Variables to replace**:
- `{{SKILL_NAME}}` - Skill identifier (automatically generated: `{project-name}-qa-skill`)
- `{{PROJECT_NAME}}` - Your project name (used in title and frontmatter)
- `{{APP_BUNDLE_ID}}` - Your app's bundle identifier
- `{{IOS_AGENT_DRIVER_DIR}}` - IOSAgentDriver project location (from environment variable)
- `{{COMMON_SCENARIOS}}` - Insert content from SCENARIOS.md

**Environment Variables**:
- `IOS_AGENT_DRIVER_DIR` - Path to IOSAgentDriver project directory (e.g., `/path/to/ios-driver`)
  - Read from environment during skill generation
  - Included in skill to help agents understand project structure
  - If not set, defaults to `[IOS_AGENT_DRIVER_DIR not set]`

**YAML Frontmatter** (automatically generated):
```yaml
---
name: {{SKILL_NAME}}           # Matches directory name (e.g., "privalia-qa-skill")
skill: {{PROJECT_NAME}} QA Testing
description: Professional iOS QA testing skill using IOSAgentDriver CLI...
version: 1.0.0
author: IOSAgentDriver CLI
tags:
  - ios
  - testing
  - qa
  - automation
---
```

**Name generation**: Project names are normalized to lowercase with hyphens:
- "Privalia" → `privalia-qa-skill`
- "My Cool App" → `my-cool-app-qa-skill`
- "MyApp123" → `myapp123-qa-skill`

### references/CLI-COMMANDS.md
Complete reference documentation for all 32 CLI commands with:
- Full syntax and parameters
- Multiple usage examples
- JSON response formats
- Common patterns and tips
- Predicate syntax reference

**No customization needed** - This file documents the CLI itself.

### SCENARIOS_TEMPLATE.md
Template for project-specific test scenarios including:
- Navigation paths and screen layouts
- Common user journeys with steps
- Test data (users, content, etc.)
- Known issues and workarounds
- Environment-specific notes

**Customize for your project** - Add your app's specific screens, flows, and test cases.

---

## Usage

### Manual Setup

1. **Copy skill directory** to your preferred location:
   ```bash
   cp -r agent-cli/skill ~/.copilot/skills/myapp-qa-skill
   ```

2. **Customize SKILL.md**:
   ```bash
   cd ~/.copilot/skills/myapp-qa-skill
   
   # Replace variables
   sed -i '' 's/{{PROJECT_NAME}}/MyApp/g' SKILL.md
   sed -i '' 's/{{APP_BUNDLE_ID}}/com.example.myapp/g' SKILL.md
   ```

3. **Create SCENARIOS.md** from template:
   ```bash
   cp SCENARIOS_TEMPLATE.md SCENARIOS.md
   
   # Edit SCENARIOS.md with your app's specific test scenarios
   nano SCENARIOS.md
   ```

4. **Insert scenarios into SKILL.md**:
   ```bash
   # Read scenarios content
   SCENARIOS=$(cat SCENARIOS.md)
   
   # Replace {{COMMON_SCENARIOS}} in SKILL.md
   # (Manual step - insert content at the {{COMMON_SCENARIOS}} marker)
   ```

5. **Verify skill**:
   - Check all variables are replaced
   - Verify scenarios are relevant
   - Test with your LLM agent

### Automated Setup (Recommended) ✅

Use the CLI command to generate and install the skill automatically:

```bash
# Interactive mode (prompts for all values)
agent-cli skill generate

# Non-interactive mode with explicit values
agent-cli skill generate \
  --project-name "MyApp" \
  --bundle-id "com.example.myapp" \
  --output ~/.copilot/skills/myapp-qa-skill

# JSON output for automation
agent-cli skill generate \
  --project-name "MyApp" \
  --bundle-id "com.example.myapp" \
  --json
```

**What it does**:
1. ✅ Copies template files to output directory
2. ✅ Replaces `{{SKILL_NAME}}`, `{{PROJECT_NAME}}`, and `{{APP_BUNDLE_ID}}` variables
3. ✅ Creates SCENARIOS.md from SCENARIOS_TEMPLATE.md
4. ✅ Installs to `~/.copilot/skills/{project-name}-qa-skill` by default

**Default output location**: `~/.copilot/skills/{project-name}-qa-skill`

**After generation**: Manually edit `SCENARIOS.md` to add your app-specific test scenarios.

---

## Skill Structure

```
myapp-qa-skill/
├── SKILL.md                      # Main skill prompt (customized)
├── SCENARIOS.md                  # Project-specific scenarios (customized)
└── references/
    └── CLI-COMMANDS.md           # CLI reference (unchanged)
```

---

## Using the Skill

### With GitHub Copilot CLI

```bash
# Copilot will automatically detect skills in ~/.copilot/skills/
# Use the skill by mentioning it:

gh copilot "using myapp-qa-skill, test the login flow"
```

### With Claude Desktop (MCP)

Configure in `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "myapp-qa": {
      "command": "agent-cli",
      "args": ["skill", "serve", "myapp-qa-skill"]
    }
  }
}
```

### With API/SDK

Load the skill prompt and pass to your LLM:
```python
# Python example
with open("~/.copilot/skills/myapp-qa-skill/SKILL.md") as f:
    skill_prompt = f.read()

response = claude.messages.create(
    system=[{"type": "text", "text": skill_prompt}],
    messages=[{
        "role": "user",
        "content": "Test the login flow for regressions"
    }]
)
```

---

## Example Agent Interaction

**User**: "Using myapp-qa-skill, check if there's any regression in the checkout flow"

**Agent (with skill)**:
```markdown
I'll test the checkout flow systematically. Let me create a test plan:

## Test Plan: Checkout Flow

**Scope**: Verify user can add items to cart and complete purchase

**Steps**:
1. Create session (iPhone 15, iOS 18.6)
2. Launch MyApp
3. Navigate to product catalog
4. Add item to cart
5. Proceed to checkout
6. Enter payment info
7. Complete purchase
8. Verify confirmation screen

Let me execute this plan...

[Agent proceeds to run commands from CLI-COMMANDS.md reference]
```

---

## Customization Tips

### Adding New Scenarios

Edit `SCENARIOS.md`:
```markdown
### New Journey: Profile Update
**Path**: Home → Settings → Profile → Edit → Save

**Steps**:
1. From home, tap settings icon
2. Tap "Profile"
3. Tap "Edit" button
4. Modify fields
5. Tap "Save"
6. Verify changes persist

**Test Commands**:
```bash
agent-cli api tap $SESSION_ID "identifier == 'settingsIcon'"
# ...more commands
```

### Adding Test Data

Edit `SCENARIOS.md`:
```markdown
### Test Users
- Premium: `premium@example.com` / `Premium123!`
- Free: `free@example.com` / `Free123!`
```

### Adding Known Issues

Edit `SCENARIOS.md`:
```markdown
### Known Issue: Search Timeout
- **Symptom**: Search takes >30s on slow network
- **Workaround**: Increase timeout to 60s
```

---

## Best Practices

1. **Keep SCENARIOS.md updated** - Add new flows as you discover them
2. **Document known issues** - Help agents avoid flaky tests
3. **Use clear identifiers** - Document accessibility IDs for key elements
4. **Version your skill** - Track changes as your app evolves
5. **Share with team** - Keep skills in source control (without secrets)

---

## Troubleshooting

### "Could not locate skill template directory"

**Problem**: `skill generate` command can't find templates.

**Solution**: Install templates manually:
```bash
mkdir -p ~/.agent-cli/skill
cp -r agent-cli/skill/* ~/.agent-cli/skill/
```

Or use the automated installer:
```bash
cd agent-cli
./build.sh install
```

### Verify Template Installation

```bash
# Check if templates are installed
ls -la ~/.agent-cli/skill/

# Should show:
# SKILL.md
# SCENARIOS_TEMPLATE.md
# references/
# README.md
```

### Template Discovery Order

The `skill generate` command searches for templates in this order:
1. Relative to executable (development mode)
2. `IOS_AGENT_DRIVER_DIR/../agent-cli/skill` (if IOS_AGENT_DRIVER_DIR is set)
3. Current working directory + `/skill`
4. `~/.agent-cli/skill` ← **Recommended location**

---

## Need Help?

- 📖 CLI Documentation: `../README.md`
- 🔍 Command Reference: `references/CLI-COMMANDS.md`
- 💡 Example Usage: See SKILL.md for complete examples

**Create professional QA testing agents with this skill template!** 🧪✨
