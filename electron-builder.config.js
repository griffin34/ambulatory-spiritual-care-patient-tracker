module.exports = {
  appId: 'org.hospital.ambulatory-patients',
  productName: 'Ambulatory Patients',
  directories: { output: 'release' },
  files: ['dist/renderer/**/*', 'src/main/**/*', 'node_modules/**/*'],
  win: {
    target: [{ target: 'portable', arch: ['x64'] }],
    icon: 'assets/icon-1.png',
    artifactName: '${productName}.exe'
  },
  mac: {
    target: [{ target: 'dmg', arch: ['x64', 'arm64'] }],
    icon: 'assets/icon-1.png',
    category: 'public.app-category.healthcare',
    artifactName: '${productName}.dmg'
  }
}
