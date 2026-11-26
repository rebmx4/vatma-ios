import test from 'node:test';
import assert from 'node:assert/strict';
import english from '../BrowserUI/assets/locale-en.js';
import spanish from '../BrowserUI/assets/locale-es.js';
import german from '../BrowserUI/assets/locale-de.js';
import french from '../BrowserUI/assets/locale-fr.js';
import portuguese from '../BrowserUI/assets/locale-pt-BR.js';
import italian from '../BrowserUI/assets/locale-it.js';
import {deviceLanguage, translate} from '../BrowserUI/assets/i18n.js';

test('the first supported device language is selected, including Brazilian Portuguese', () => {
  assert.equal(deviceLanguage(['ja-JP', 'pt-BR', 'es-MX']), 'pt-BR');
  assert.equal(deviceLanguage(['fr-CA', 'en-US']), 'fr');
  assert.equal(deviceLanguage(['it-IT']), 'it');
  assert.equal(deviceLanguage(['ja-JP']), 'en');
});

test('each interface dictionary keeps every label and its interpolation parameters', () => {
  const parameters = text => [...text.matchAll(/\{\w+\}/g)].map(match => match[0]).sort();
  for (const [language, catalog] of Object.entries({en:english,es:spanish,de:german,fr:french,'pt-BR':portuguese,it:italian})) {
    assert.deepEqual(Object.keys(catalog).sort(), Object.keys(english).sort(), language);
    for (const [key, expected] of Object.entries(english)) {
      const result = translate(key, language);
      assert.equal(result, catalog[key], `${language}: ${key}`);
      assert.deepEqual(parameters(result), parameters(expected), `${language}: ${key}`);
    }
  }
  assert.equal(translate('Искать «{value}»', 'es', {value: 'ATMA'}), 'Buscar «ATMA»');
  assert.equal(translate('Открытые вкладки: 12', 'de'), 'Offene Tabs: 12');
});
