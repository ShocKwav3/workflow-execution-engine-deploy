// Prints a Markdown report of the Checkov and Trivy JSON files in a folder, one collapsed section per file.
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";

const MAX_ROWS = 50;

const dir = process.argv[2];

if (!dir) {
  console.error("usage: node security-report.mjs <reports folder>");
  process.exit(1);
}

function checkovRows(report) {
  // One framework per file; Checkov writes an array when a run covers several.
  const runs = Array.isArray(report) ? report : [report];

  return runs.flatMap((run) =>
    (run.results?.failed_checks ?? []).map(
      (check) =>
        `| \`${check.check_id}\` | ${check.check_name} | \`${check.resource}\` | \`${check.file_path}:${check.file_line_range.join("-")}\` |`,
    ),
  );
}

function trivyRows(report) {
  return (report.Results ?? []).flatMap((result) =>
    (result.Vulnerabilities ?? []).map(
      (vuln) =>
        `| \`${vuln.VulnerabilityID}\` | ${vuln.Severity} | \`${vuln.PkgName}\` | ${vuln.InstalledVersion} | ${vuln.FixedVersion ?? ""} |`,
    ),
  );
}

const scanners = [
  {
    prefix: "checkov-",
    label: "Checkov",
    header: "| Check | Name | Resource | File |\n|---|---|---|---|",
    rows: checkovRows,
  },
  {
    prefix: "trivy-",
    label: "Trivy",
    header: "| CVE | Severity | Package | Installed | Fixed |\n|---|---|---|---|---|",
    rows: trivyRows,
  },
];

function section(title, header, rows) {
  if (rows.length === 0) {
    return `- ✅ ${title}: no findings\n`;
  }

  const lines = [
    `<details><summary>⚠️ ${title}: ${rows.length} findings</summary>`,
    "",
    header,
    ...rows.slice(0, MAX_ROWS),
  ];

  if (rows.length > MAX_ROWS) {
    lines.push("", `Showing ${MAX_ROWS} of ${rows.length}. The job log has the full list.`);
  }

  lines.push("", "</details>", "");

  return lines.join("\n");
}

const files = existsSync(dir) ? readdirSync(dir).sort() : [];
const output = [];

for (const scanner of scanners) {
  for (const file of files.filter(
    (name) => name.startsWith(scanner.prefix) && name.endsWith(".json"),
  )) {
    const report = JSON.parse(readFileSync(path.join(dir, file), "utf8"));
    const name = file.slice(scanner.prefix.length, -".json".length);

    output.push(section(`${scanner.label} ${name}`, scanner.header, scanner.rows(report)));
  }
}

console.log(
  output.length > 0 ? output.join("\n") : "No security reports were found. Check the scan jobs.",
);
