# Requires powershell-yaml module

$basePath = Split-Path -Path $PSScriptRoot -Parent
$cleanPath = Join-Path $basePath "policies/yaml/clean"
$docsPath = Join-Path $basePath "analysis/visualizations"

# Create docs directory
$null = New-Item -ItemType Directory -Force -Path $docsPath

function Get-SafeId {
    param($text)
    $id = $text -replace '[^a-zA-Z0-9]', '_'
    return $id.ToLower()
}

function Get-PolicyGraph {
    param($policies)
    
    $nodes = [System.Collections.ArrayList]@()
    $links = [System.Collections.ArrayList]@()
    $nodeIndex = @{}

    # Helper function to add node and get its index
    function Add-Node {
        param($id, $name, $type, $state = $null)
        if (-not $nodeIndex.ContainsKey($id)) {
            $node = @{
                id = $id
                name = $name
                type = $type
            }
            if ($state) {
                $node.state = $state
            }
            $null = $nodes.Add($node)
        }
        return $id # Return the ID instead of index
    }

    # Add nodes and links
    foreach ($policy in $policies) {
        $policyId = Get-SafeId $policy.displayName
        $policyNode = Add-Node $policyId $policy.displayName "policy" $policy.state

        # Process users
        if ($policy.conditions.users.includeUsers) {
            foreach ($user in $policy.conditions.users.includeUsers) {
                $userId = Get-SafeId $user
                $userNode = Add-Node $userId $user "user"
                $null = $links.Add(@{
                    source = $userNode      # Use IDs instead of indices
                    target = $policyNode    # Use IDs instead of indices
                    type = "includes"
                })
            }
        }

        # Process applications
        if ($policy.conditions.applications.includeApplications) {
            foreach ($app in $policy.conditions.applications.includeApplications) {
                $appId = Get-SafeId $app
                $appNode = Add-Node $appId $app "application"
                $null = $links.Add(@{
                    source = $policyNode    # Use IDs instead of indices
                    target = $appNode       # Use IDs instead of indices
                    type = "protects"
                })
            }
        }

        # Process controls
        if ($policy.grantControls.builtInControls) {
            foreach ($control in $policy.grantControls.builtInControls) {
                $controlId = Get-SafeId $control
                $controlNode = Add-Node $controlId $control "control"
                $null = $links.Add(@{
                    source = $policyNode     # Use IDs instead of indices
                    target = $controlNode    # Use IDs instead of indices
                    type = "requires"
                })
            }
        }
    }

    # Convert to proper format
    return @{
        nodes = [array]$nodes
        links = [array]$links
    } | ConvertTo-Json -Depth 10 -Compress
}

# Read all policies
$policies = @()
Get-ChildItem -Path $cleanPath -Filter "*.yaml" | ForEach-Object {
    $yamlContent = Get-Content $_.FullName -Raw
    $policy = ConvertFrom-Yaml $yamlContent
    $policies += $policy
}

# Generate graph data
$graphData = Get-PolicyGraph $policies

# Create interactive visualization with embedded template
$html = @'
<!DOCTYPE html>
<html>
<head>
    <title>Conditional Access Policy Visualization</title>
    <script src="https://d3js.org/d3.v7.min.js"></script>
    <style>
        body { margin: 0; padding: 20px; }
        #graph {
            width: 100%;
            height: 90vh;
            border: 1px solid #ccc;
            border-radius: 4px;
            background: #f8f9fa;
        }
        .node {
            cursor: pointer;
            stroke: #333;
            stroke-width: 1.5px;
        }
        .node text {
            font-size: 12px;
            fill: #333;
            text-anchor: middle;
        }
        .link {
            stroke: #999;
            stroke-opacity: 0.6;
            stroke-width: 1px;
        }
        .policy { fill: #f9f; }
        .user { fill: #bbf; }
        .application { fill: #bfb; }
        .control { fill: #fbb; }
        .tooltip {
            position: absolute;
            background: white;
            padding: 8px;
            border: 1px solid #333;
            border-radius: 4px;
            pointer-events: none;
            font-size: 12px;
            box-shadow: 2px 2px 6px rgba(0,0,0,0.2);
        }
    </style>
</head>
<body>
    <div id="graph"></div>
    <script>
        // Create the visualization after the DOM is loaded
        document.addEventListener("DOMContentLoaded", () => {
            const data = DATA_PLACEHOLDER;
            const width = document.querySelector("#graph").clientWidth;
            const height = document.querySelector("#graph").clientHeight;
            
            // Initialize with some spread
            data.nodes.forEach(node => {
                node.x = width / 2 + (Math.random() - 0.5) * 500;
                node.y = height / 2 + (Math.random() - 0.5) * 500;
            });

            // Create force simulation first
            const simulation = d3.forceSimulation(data.nodes)
                .force("link", d3.forceLink()
                    .id(d => d.id)
                    .links(data.links)
                    .distance(150))
                .force("charge", d3.forceManyBody().strength(-2000))
                .force("center", d3.forceCenter(width / 2, height / 2))
                .force("collision", d3.forceCollide().radius(60));

            // Drag functions defined before use
            function dragstarted(event, d) {
                if (!event.active) simulation.alphaTarget(0.3).restart();
                d.fx = d.x;
                d.fy = d.y;
            }

            function dragged(event, d) {
                d.fx = event.x;
                d.fy = event.y;
            }

            function dragended(event, d) {
                if (!event.active) simulation.alphaTarget(0);
                d.fx = null;
                d.fy = null;
            }

            // Create SVG
            const svg = d3.select("#graph")
                .append("svg")
                .attr("width", "100%")
                .attr("height", "100%");

            const g = svg.append("g");

            // Add zoom behavior
            svg.call(d3.zoom()
                .scaleExtent([0.1, 4])
                .on("zoom", (event) => {
                    g.attr("transform", event.transform);
                }));

            // Create tooltip
            const tooltip = d3.select("body").append("div")
                .attr("class", "tooltip")
                .style("opacity", 0);

            // Draw links
            const link = g.append("g")
                .selectAll("line")
                .data(data.links)
                .join("line")
                .attr("class", "link");

            // Draw nodes
            const node = g.append("g")
                .selectAll("g")
                .data(data.nodes)
                .join("g")
                .attr("class", "node")
                .call(d3.drag()
                    .on("start", dragstarted)
                    .on("drag", dragged)
                    .on("end", dragended));

            // Add circles to nodes
            node.append("circle")
                .attr("r", d => d.type === "policy" ? 20 : 10)
                .attr("class", d => d.type);

            // Add labels with background
            node.append("text")
                .attr("dy", 30)
                .style("font-size", "10px")
                .style("background", "white")
                .text(d => d.name.length > 20 ? d.name.substring(0, 20) + "..." : d.name);

            // Add emoji indicators for policies
            node.filter(d => d.type === "policy")
                .append("text")
                .attr("dy", 5)
                .text(d => {
                    switch(d.state) {
                        case "enabled": return "✅";
                        case "disabled": return "❌";
                        case "enabledForReportingButNotEnforced": return "📊";
                        default: return "❓";
                    }
                });

            // Update positions on tick
            simulation.on("tick", () => {
                link
                    .attr("x1", d => d.source.x)
                    .attr("y1", d => d.source.y)
                    .attr("x2", d => d.target.x)
                    .attr("y2", d => d.target.y);

                node.attr("transform", d => `translate(${d.x},${d.y})`);
            });

            // Add mouseover effects
            node
                .on("mouseover", (event, d) => {
                    tooltip.transition()
                        .duration(200)
                        .style("opacity", .9);
                    tooltip.html(`Type: ${d.type}<br/>Name: ${d.name}${d.state ? `<br/>State: ${d.state}` : ""}`)
                        .style("left", (event.pageX + 10) + "px")
                        .style("top", (event.pageY - 28) + "px");
                })
                .on("mouseout", () => {
                    tooltip.transition()
                        .duration(500)
                        .style("opacity", 0);
                });

            // Add legend
            const legend = svg.append("g")
                .attr("class", "legend")
                .attr("transform", "translate(20,20)");

            const legendData = [
                {type: "policy", label: "Policy"},
                {type: "user", label: "User"},
                {type: "application", label: "Application"},
                {type: "control", label: "Control"}
            ];

            const legendItems = legend.selectAll("g")
                .data(legendData)
                .join("g")
                .attr("transform", (d, i) => `translate(0,${i * 20})`);

            legendItems.append("circle")
                .attr("r", 6)
                .attr("class", d => d.type);

            legendItems.append("text")
                .attr("x", 15)
                .attr("y", 5)
                .text(d => d.label);
        });
    </script>
</body>
</html>
'@

# Replace the placeholder with actual data
$html = $html.Replace('DATA_PLACEHOLDER', $graphData)

$html | Out-File (Join-Path $docsPath "policy-visualization.html") -Encoding UTF8

Write-Host "Visualization generated in $docsPath/policy-visualization.html"
