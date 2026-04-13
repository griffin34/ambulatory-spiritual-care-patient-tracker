function seedLovs(db) {
  const insert = db.prepare('INSERT OR IGNORE INTO list_of_values (category, value, sort_order) VALUES (?, ?, ?)')
  const lovs = [
    ['referral_source','Physician Referral',1],['referral_source','Hospital',2],
    ['referral_source','Self Referral',3],['referral_source','Family Member',4],
    ['referral_source','Social Worker',5],['referral_source','Other',6],
    ['religion','Catholic',1],['religion','Protestant',2],['religion','Jewish',3],
    ['religion','Muslim',4],['religion','Hindu',5],['religion','Buddhist',6],
    ['religion','Non-Religious',7],['religion','Other',8],
    ['language','English',1],['language','Spanish',2],['language','Mandarin',3],
    ['language','Polish',4],['language','Hindi',5],['language','Other',6],
    ['appointment_type','Telemed',1],['appointment_type','Video',2],
  ]
  const seedMany = db.transaction((rows) => rows.forEach(r => insert.run(...r)))
  seedMany(lovs)
}

module.exports = { seedLovs }
