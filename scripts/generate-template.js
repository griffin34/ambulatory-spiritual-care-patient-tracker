const xlsx = require('xlsx')
const path = require('path')

const headers = [
  'last_name', 'first_name', 'middle_name', 'mrn', 'phone',
  'date_of_referral', 'referral_source', 'religion', 'language',
  'current_status', 'appt_date', 'appt_time', 'appt_type',
  'consultant', 'appt_status', 'is_last_appointment', 'notes'
]

const exampleRow = [
  'Smith', 'John', 'A', 'MRN-001', '760-555-0101',
  '2025-01-10', 'Physician Referral', 'Catholic', 'English',
  'completed', '2025-01-24', '10:00', 'Video',
  'Frances', 'completed', 'yes', 'Initial visit completed'
]

const ws = xlsx.utils.aoa_to_sheet([headers, exampleRow])
const wb = xlsx.utils.book_new()
xlsx.utils.book_append_sheet(wb, ws, 'patients_and_appointments')

const outPath = path.join(__dirname, '../docs/patient_import_template.xlsx')
xlsx.writeFile(wb, outPath)
console.log('Template written to', outPath)
