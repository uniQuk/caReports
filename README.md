# Conditional Access Policy Reporting Scripts

A collection of PowerShell scripts for analyzing, documenting, and visualising Microsoft Entra ID (Azure AD) Conditional Access policies.

---
# Update: 10th February 2025
Added 4 additional optional scripts:
- Module Dependency:
  - Install-Module powershell-yaml
  - Install-Module powershell-yaml -Scope CurrentUser
  - Import-Module powershell-yaml
- Require running either of the 01-fetch_ca_policies..ps1
```
│   ├── 05-json_to_yaml.ps1
│   ├── 06-clean_yaml.ps1
│   ├── 07-yaml_summary.ps1
│   └── 08-generate-d3-graph.ps1 (experimental/WIP)
```

- 05 - Converts the json policies to YAML
- 06 - Removes empty values for easier viewing
- 07 - Uses the cleaned YAML from 06 to generate a markdown report of all policies
- 08 - Experimental script using D3.js to visualise policy relationships. (Work in Progress)

ToDo:
- Convert to a PowerShell module, update the file structure and simplify the outputs
---


## ⚠️ Disclaimer

These scripts are provided "AS IS" without warranty of any kind. This is a personal project and is not officially supported by Microsoft. Before using in a production environment:

- Review all code carefully before execution
- Test in a non-production environment first
- Ensure you understand the impact of each script
- Be aware that improper use could impact your organization's security policies
- Consider rate limiting and API throttling in large environments
- You are responsible for managing access permissions and maintaining security

These scripts are intended for assessment and documentation purposes only. Users are responsible for validating the scripts' behavior and ensuring compliance with their organization's security requirements.

## Prerequisites

- PowerShell 7.0 or later
- Microsoft Graph PowerShell SDK modules:
  - Microsoft.Graph.Identity.SignIns
  - Microsoft.Graph.Groups
  - Microsoft.Graph.Users
  - Microsoft.Graph.Identity.DirectoryManagement
- Appropriate permissions in Microsoft Entra ID:
  - Policy.Read.All
  - Directory.Read.All
  - User.Read.All
  - Group.Read.All
  - Application.Read.All

## Directory Structure

```
cagaps/
├── scripts/
│   ├── 01-fetch_ca_policies_dev.ps1
│   ├── 01-fetch_ca_policies_prod.ps1
│   ├── 02-generate_diagrams_data.ps1
│   ├── 02-generate_diagrams_original.ps1
│   ├── 03-analyze_policies.ps1
│   ├── 04-ca-naming.ps1
│   ├── 05-json_to_yaml.ps1
│   ├── 06-clean_yaml.ps1
│   ├── 07-yaml_summary.ps1
│   └── 08-generate-d3-graph.ps1
├── config/
│   └── naming-rules.json
├── diagrams/
│   ├── original/    # Generated policy diagrams
│   ├── data/        # Generated policy diagrams
├── policies/
│   ├── original/    # Original policy JSON files
│   ├── data/        # Enhanced policy JSON files
└── analysis/
    └── markdown/    # Analysis reports and documentation
```

## Scripts Overview

### 1. Policy Fetching Scripts
- Both scripts parse friendly names from GUID's for Roles, Groups, Applications etc
- Stores verbose .json and creates enhanced JSON files with resolved names for users, groups, and applications
- _dev.ps1 also gets all users within any included/excluded groups hence not suitable for large tenants
- _prod.ps1 stores group member count instead

#### `01-fetch_ca_policies_dev.ps1` (Suitable for small/dev tenants)
- Fetches Conditional Access policies with basic metadata
- Suitable for environments with fewer policies (creates larger .json files)
- Saves both original and enhanced versions of policies
- Parses friendly names from guid's and stores all group members:
```js
"excludeGroups": {
        "9876538c-1234-5678-8e1f-12345abcdefg": {
          "members": {
            "123abc-12ab-1b1b-a3a3-abcd1234ef5": {
              "userPrincipalName": "user@domain.com",
              "displayName": "First Last",
              "id": "123abc-12ab-1b1b-a3a3-abcd1234ef5"
            }
          },
          "displayName": "Group Name",
          "id": "9876538c-1234-5678-8e1f-12345abcdefg"
        }
      },
```

#### `01-fetch_ca_policies_prod.ps1` (Suitable for larger tenants)
- Extended version with additional error handling and group member counting
- Better suited for large environments
- Parses friendly names from guid's stores group member count instead of users:
```js
"includeGroups": {
  "9876538c-1234-5678-8e1f-12345abcdefg": {
    "displayName": "Group Name",
    "memberCount": 17,
    "id": "9876538c-1234-5678-8e1f-12345abcdefg"
  }
},
```


### 2. Policy Visualization Scripts
***Note:*** Inspired by the visualiser provided in the [MEMPSToolkit](https://github.com/hcoberdalhoff/MEMPSToolkit)

#### `02-generate_policy_diagrams.ps1`
- Creates Mermaid.js diagrams for each policy
- Creates markdown files within a ```mermaid``` code block. 
  - Used with "Markdown Preview Mermaid Support" VS Code extension. Otherwise can be saved as .mmd and remove the ```mermaid``` code block
- Visualizes policy components including:
  - User conditions
  - Application scope
  - Platform requirements
  - Grant controls
- Saves diagrams as Markdown files for easy viewing

#### `02-generate_diagrams_original.ps1` (Original folder)
- This uses the verbose unmodified .json files in /policies/original
- Uses guid's instead of friendly names
- Original version of the diagram generator
- Includes simpler diagrams
- Useful for detailed technical documentation

#### `02-generate_policy_diagrams.ps1` (Data folder)
- This uses the enhanced .json files in /policies/data
- Generates friendly names (or numbers in groups dependent on which fetch script is ran)
- Groups directory roles, groups, users into larger boxes to help visualise large inclusions/exclusions
- Includes more detailed but potentially more complex diagrams
- Useful for detailed technical documentation

### 3. Policy Analysis Script

#### `03-analyze_policies.ps1`
- Performs an analysis of policy configurations
- Generates comprehensive Markdown report including:
  - Policy patterns and statistics
  - Temporal analysis (policy changes over time)
  - State distribution
  - Control usage patterns

### 4. Policy Naming Convention Script

- This is a proof of concept using a simple rules based .json file to generate suggested naming for existing conditional access policies. 
  - /config/naming-rules.json

#### `04-ca-naming.ps1`
- Analyzes and suggests standardized names for policies
- Implements multiple naming conventions:
  - Simple MS Format (e.g., CA01-Apps-Response-Users-Conditions)
    - Ref: [Microsoft Plan Conditional Access](https://learn.microsoft.com/en-us/entra/identity/conditional-access/)plan-conditional-access#set-naming-standards-for-your-policies
  - MS Persona Format (e.g., CA001-Persona-PolicyType-Target-Platform-Controls)
    - Ref: [Microsoft Conditional Access Framework](https://learn.microsoft.com/en-us/azure/architecture/guide/security/conditional-access-framework)  
  - ASD Format (e.g., ADM-B-Purpose)
    - Ref: [ASD's Blueprint for Secure Cloud](https://blueprint.asd.gov.au/design/platform/identity/conditional-access/)
- Uses configuration from `config/naming-rules.json`

### 5. JSON to YAML Conversion Script

#### `05-json_to_yaml.ps1`
Converts JSON policy files to YAML format for better readability and analysis.

Features:
- Generates safe filenames using MD5 hashing
- Creates a manifest file mapping short names to original policy names
- Preserves original policy structure while making it more readable
- Handles special characters and long filenames safely

### 6. YAML Cleaning Script

#### `06-clean_yaml.ps1`
Cleans and normalizes YAML policy files for consistent analysis.

Features:
- Removes empty values, arrays, and objects
- Standardizes property ordering (displayName, state, dates, etc.)
- Preserves essential policy structure
- Makes files more consistent for comparison and analysis

### 7. YAML Summary Script

#### `07-yaml_summary.ps1`
Generates a comprehensive markdown summary of all policies.

Features:
- Creates a table of contents for all policies
- Shows detailed information for each policy
- Highlights relationships between policies
- Includes state indicators (enabled, disabled, report-only)

### 8. D3 Graph Generation Script

#### `08-generate-d3-graph.ps1`
Creates an interactive visualization of policy relationships (experimental).

## Usage

1. Start by fetching policies:
```powershell
Connect-MgGraph -Scopes "Policy.Read.All", "Directory.Read.All"
./scripts/01-fetch_ca_policies_sm.ps1  # or large version for bigger environments
```

2. Generate visualizations:
```powershell
./scripts/02-generate_policy_diagrams.ps1
```

3. Analyze policies:
```powershell
./scripts/03-analyze_policies.ps1
```

4. Generate naming convention analysis:
```powershell
./scripts/04-ca-naming.ps1
```

5. Convert JSON to YAML:
```powershell
./scripts/05-json_to_yaml.ps1
```

6. Clean YAML files:
```powershell
./scripts/06-clean_yaml.ps1
```

7. Generate YAML summary:
```powershell
./scripts/07-yaml_summary.ps1
```

8. Generate D3 graph:
```powershell
./scripts/08-generate-d3-graph.ps1
```

## Output Files

- `policies/original/*.json`: Raw policy exports
- `policies/data/*.json`: Enhanced policies with resolved names
- `diagrams/original/*.md`: Mermaid diagrams for each policy
- `diagrams/data/*.md`: Mermaid diagrams for each policy
- `analysis/markdown/policy_analysis.md`: Comprehensive analysis report
- `analysis/markdown/naming_conventions.md`: Naming convention analysis
- `policies/yaml/*.yaml`: YAML converted policy files
- `policies/yaml/cleaned/*.yaml`: Cleaned YAML policy files
- `analysis/markdown/yaml_summary.md`: YAML summary report
- `diagrams/d3/*.html`: D3 interactive graph visualizations

## Configuration

The `config/naming-rules.json` file contains mappings and rules for:
- Application name abbreviations
- Naming sequence numbers
- Policy type classifications
- Purpose definitions for different policy scenarios

## Common Tasks

### Adding New Policies
1. Run the fetch script to update local copies
2. Generate new diagrams
3. Update analysis and naming reports

### Reviewing Policy Changes
1. Run the fetch script to get current state
2. Compare with previous versions in git
3. Review temporal analysis section in analysis report

### Standardizing Policy Names
1. Run the naming convention analysis
2. Review suggestions in naming_conventions.md
3. Update policy names in Entra ID based on recommendations

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request with a clear description of changes

## License

MIT License - See LICENSE file for details