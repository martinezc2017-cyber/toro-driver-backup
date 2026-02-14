const fs = require('fs');
const path = require('path');

// Simple PDF text extractor - reads raw bytes and finds text between parentheses
// Works without external dependencies for simple PDFs
const files = [
  'C:\\Users\\marti\\Downloads\\statement_Feb 10, 10_23 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Feb 9, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Feb 2, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Jan 26, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Jan 19, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Jan 12, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Jan 5, 4_00 AM (1).pdf',
  'C:\\Users\\marti\\Downloads\\statement_Dec 29, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Dec 22, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Dec 15, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Dec 8, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Dec 1, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Nov 24, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Nov 17, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Nov 10, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Nov 3, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Oct 20, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Oct 13, 4_00 AM.pdf',
  'C:\\Users\\marti\\Downloads\\statement_Oct 6, 4_00 AM.pdf',
];

async function main() {
  let pdfParse;
  try {
    pdfParse = require('pdf-parse');
  } catch(e) {
    // Install it first
    const { execSync } = require('child_process');
    console.log('Installing pdf-parse...');
    execSync('npm install pdf-parse --prefix ' + __dirname, { stdio: 'pipe' });
    pdfParse = require(path.join(__dirname, 'node_modules', 'pdf-parse'));
  }

  for (const file of files) {
    try {
      if (!fs.existsSync(file)) {
        console.log(`--- SKIP: ${path.basename(file)} ---\n`);
        continue;
      }
      const buf = fs.readFileSync(file);
      const data = await pdfParse(buf);
      console.log(`=== ${path.basename(file)} ===`);
      console.log(data.text.substring(0, 3000));
      console.log('\n');
    } catch (e) {
      console.log(`ERROR: ${path.basename(file)}: ${e.message}\n`);
    }
  }
}

main();
