import test from 'node:test';
import assert from 'node:assert/strict';
import english from '../BrowserUI/assets/locale-en.js';
import spanish from '../BrowserUI/assets/locale-es.js';
import german from '../BrowserUI/assets/locale-de.js';
import french from '../BrowserUI/assets/locale-fr.js';
import portuguese from '../BrowserUI/assets/locale-pt-BR.js';
import italian from '../BrowserUI/assets/locale-it.js';
import chineseSimplified from '../BrowserUI/assets/locale-zh-Hans.js';
import korean from '../BrowserUI/assets/locale-ko.js';
import japanese from '../BrowserUI/assets/locale-ja.js';
import {deviceLanguage, translate} from '../BrowserUI/assets/i18n.js';

test('the first supported device language is selected, including Brazilian Portuguese', () => {
  assert.equal(deviceLanguage(['vi-VN', 'pt-BR', 'es-MX']), 'pt-BR');
  assert.equal(deviceLanguage(['fr-CA', 'en-US']), 'fr');
  assert.equal(deviceLanguage(['it-IT']), 'it');
  assert.equal(deviceLanguage(['vi-VN']), 'en');
});

test('device preferences choose Japanese, Korean and Simplified Chinese without silently replacing Traditional Chinese', () => {
  assert.equal(deviceLanguage(['ja-JP', 'en-US']), 'ja');
  assert.equal(deviceLanguage(['ko-KR', 'en-US']), 'ko');
  for (const tag of ['zh', 'zh-Hans', 'zh_CN', 'zh-SG', 'zh-Hans-HK']) {
    assert.equal(deviceLanguage([tag]), 'zh-Hans', tag);
  }
  assert.equal(deviceLanguage(['zh-Hant', 'zh-TW', 'zh-HK', 'zh-MO', 'ja-JP']), 'ja');
});

test('each interface dictionary keeps every label and its interpolation parameters', () => {
  const parameters = text => [...text.matchAll(/\{\w+\}/g)].map(match => match[0]).sort();
  const catalogs = {
    en:english,es:spanish,de:german,fr:french,'pt-BR':portuguese,it:italian,
    'zh-Hans':chineseSimplified,ko:korean,ja:japanese,
  };
  for (const [language, catalog] of Object.entries(catalogs)) {
    assert.deepEqual(Object.keys(catalog).sort(), Object.keys(english).sort(), language);
    for (const [key, expected] of Object.entries(english)) {
      const result = translate(key, language);
      assert.equal(result, catalog[key], `${language}: ${key}`);
      assert.deepEqual(parameters(result), parameters(expected), `${language}: ${key}`);
    }
  }
  assert.equal(translate('Искать «{value}»', 'es', {value: 'ATMA'}), 'Buscar «ATMA»');
  assert.equal(translate('Открытые вкладки: 12', 'de'), 'Offene Tabs: 12');
  assert.equal(translate('Открытые вкладки: 12', 'zh-Hans'), '已打开 12 个标签页');
  assert.equal(translate('Открыть через {method}', 'ko', {method:'Face ID'}), 'Face ID(으)로 잠금 해제');
  assert.equal(translate('Искать «{value}»', 'ja', {value:'ATMA'}), '「ATMA」を検索');
});
