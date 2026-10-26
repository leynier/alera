const { engines } = await Bun.file('package.json').json();
const node = Bun.spawnSync(['node', '--version']);
if (node.exitCode !== 0) {
  throw new Error('Cannot determine the installed Node.js version');
}

const versions = {
  node: node.stdout.toString().trim(),
  bun: Bun.version,
};
for (const [name, version] of Object.entries(versions)) {
  const required = engines?.[name];
  if (typeof required !== 'string' || !Bun.semver.satisfies(version, required)) {
    throw new Error(`${name} ${version} does not satisfy ${required}`);
  }
  console.log(`${name} ${version} satisfies ${required}`);
}
