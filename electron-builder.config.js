module.exports = {
  appId: 'org.hospital.ambulatory-patients',
  productName: 'Ambulatory Patients',
  directories: { output: 'release' },
  files: ['dist/renderer/**/*', 'src/main/**/*', 'node_modules/**/*'],
  win: {
    target: [{ target: 'portable', arch: ['x64'] }],
    icon: 'assets/icon.ico'
  }
}
