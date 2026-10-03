// Epic 8 — turns kg CO2e into something people can picture (mentor
// feedback: "6.1 kg CO2e" on its own isn't relatable).
//
// Comparison chosen: litres of petrol burned. It needs only one published
// factor, with no assumption about a car's fuel efficiency (unlike "km
// driven"), and it's the same factor Malaysia's own government carbon
// calculator uses for petrol.
//
// Source: UK DEFRA 2023 GHG conversion factors, petrol, 2.34502 kg CO2e
// per litre — as adopted by MGTC (Malaysian Green Technology and Climate
// Change Corporation) in its LCOS Personal Carbon Footprint calculator,
// https://www.mgtc.gov.my/lcos-personal-calculator/
//
// Kept as a named constant with its source here (rather than a DB table)
// because it's a single value that changes at most once a year.
const PETROL_KG_CO2E_PER_LITRE = 2.34502;
const PETROL_SOURCE_NAME = 'DEFRA 2023 conversion factor for petrol, as used by MGTC Malaysia';

function petrolLitresFor(kgCo2e) {
  return kgCo2e / PETROL_KG_CO2E_PER_LITRE;
}

module.exports = { PETROL_KG_CO2E_PER_LITRE, PETROL_SOURCE_NAME, petrolLitresFor };
