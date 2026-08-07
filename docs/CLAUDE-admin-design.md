# Ana-Bala · Админ-панель — полная дизайн-система

Спецификация для точного воспроизведения. Не «вдохновляйся» — **собирай по этим рецептам**.
Эталон макетов: `Ana-Bala Admin.dc.html` — 76 кадров, 1440 × 900. Если что-то расходится с этим файлом, прав файл.

**Можно менять:** внешний вид, плотность, порядок колонок, тексты подписей и пустых состояний.
**Нельзя менять:** запросы, роли и права, схему данных, статусы заказов, названия полей, форматы экспорта. Панель работает на боевом сервере, ей пользуются каждый день.

---

# ЧАСТЬ 1 · ПОЧЕМУ АДМИНКА ВЫГЛЯДИТ ИНАЧЕ

Оператор смотрит в неё восемь часов и работает с клавиатуры. Тёплую палитру приложения сюда переносить нельзя.

| | Приложение | Админка |
|---|---|---|
| Строка списка | 68 px | **40 px** |
| Базовый текст | 15 px | **13 px** |
| Радиус карточки | 20–26 | **10** |
| Цвет | акцент на каждом экране | только статус |
| Шрифт | Rubik | **Manrope + JetBrains Mono** |

---

# ЧАСТЬ 2 · ТОКЕНЫ

## 2.1 Холст

```
Кадр                1440 × 900
Сайдбар             216 px фикс. (flex:0 0 216px)
Контент             flex:1; min-width:0   ← min-width обязателен
Топбар              56 px (flex:0 0 56px)
Поля контента       18px 22px
Между блоками       12–16 px
Высота кнопки       34 px (топбар), 36–38 px (в карточке)
Доступная высота    802 px = 900 − 56 топбар − 40 padding
```

`overflow:hidden` на кадре, `min-height:0` на всех flex-контейнерах внутри — иначе таблицы выдавливают подвал.

## 2.2 Шрифты

```html
<link href="https://fonts.googleapis.com/css2?family=Manrope:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
```

```css
body { font-family: Manrope, system-ui, sans-serif; font-variant-numeric: tabular-nums; }
```
`tabular-nums` обязателен — цифры в колонках должны выравниваться.

**JetBrains Mono** — номера заказов, артикулы, серийники, время, ключи API, суммы в журналах.

| Роль | px | weight |
|---|---|---|
| Заголовок страницы (топбар) | 17 | 700 |
| Заголовок карточки | 15 | 700 |
| Метрика | 26 | 800 |
| Крупная метрика (дашборд) | 26–28 | 800, `letter-spacing:-.02em` |
| Таблица | 13 | 500–600 |
| Шапка таблицы | 11 | 700, uppercase, `letter-spacing:.06em`, `#7A7076` |
| Подпись | 12 | 500, `#7A7076` |
| Метка поля | 11–12 | 700, uppercase, `.06em`, `#7A7076` |

## 2.3 Цвета

```css
--app-bg:      #E8E4E0;   /* фон вокруг кадра */
--work-bg:     #F4F1EE;   /* рабочая область */
--gallery-bg:  #EFEBE7;   /* фон галерей форм */
--card:        #FFFFFF;
--thead:       #FAF8F6;
--border:      #D8D2CE;
--border-soft: #C9C2BD;   /* внешние рамки, модалки */
--row-divider: #F2EEEB;
--field-bg:    #F4F1EE;

--ink:         #1E1A1D;
--ink-2:       #544C51;
--ink-3:       #7A7076;
--ink-4:       #8A8085;
--ink-mute:    #A8949F;   /* шевроны */

--sidebar:     #1E1A1D;
--side-ink:    #B3AAAF;
--side-group:  #6B6067;   /* заголовок группы */
--side-dim:    #8F868C;   /* неактивный подпункт */
--side-alert:  #FF6B8F;   /* «Экстренные» */
--side-line:   #332C31;
--side-avatar: #3A3238;
--side-meta:   #5A5158;   /* версия */

--action:      #C2003F;
--danger:      #A8002F;
--ok:          #1E7A54;  --ok-bg:   #EDF5F1;  --ok-border: #CFE5DA;
--warn:        #8A5A00;  --warn-ind:#E0A33C;  --warn-bg:  #FDF6EA;  --warn-border:#EBD9B8;
--warn-deep:   #6E4A00;
--err-bg:      #FBF0F3;  --err-border:#E8C3CF;  --err-text: #8A1240;
--neutral:     #544C51;  --neutral-bg:#F0EDEA;
--violet:      #4C31C4;  --violet-bg:#F1ECFF;  --violet-border:#D7CCFF;  --violet-deep:#3B2A8C;
--info:        #1F5FBF;  --info-bg:  #E9F0FB;

/* графики */
--g-bundle: #C2003F;  --g-watch: #E0A33C;  --g-tag: #3D8C6E;  --g-content: #4C31C4;
--g-track:  #EDE8E4;  --g-pink:  #E7C8D4;
```

**Правило цвета:** малиновый только для действия и просрочки. «Нужно посмотреть» — янтарное. Зелёный — подтверждение факта, не украшение. Строка красится **фоном**, не текстом.

## 2.4 Форма

```
радиусы: 5 статус-чип · 6–8 кнопки и мелкие элементы · 10 карточка · 12 модалка и внешний кадр · 999 круглые бейджи
тень: карточки — нет (только border), модалка — 0 18px 44px rgba(30,20,26,.22), панель галереи — 0 10px 26px rgba(30,20,26,.10)
подложка модалки: rgba(30,20,26,.42)
```

---

# ЧАСТЬ 3 · КОМПОНЕНТЫ (копировать буквально)

## 3.1 Кадр

```html
<div style="width:1440px;height:900px;background:#F4F1EE;border:1px solid #C9C2BD;border-radius:14px;overflow:hidden;display:flex">
  <!-- сайдбар -->
  <div style="flex:1;min-width:0;display:flex;flex-direction:column">
    <!-- топбар --><!-- контент -->
  </div>
</div>
```
Для кадров с модалкой поверх — добавить `position:relative` на кадр.

## 3.2 Сайдбар — точная структура

```html
<div style="width:216px;flex:0 0 216px;background:#1E1A1D;color:#B3AAAF;display:flex;flex-direction:column;padding:16px 12px;overflow:hidden">

  <!-- логотип -->
  <div style="display:flex;align-items:center;gap:10px;padding:0 8px 14px">
    <div style="width:30px;height:30px;border-radius:9px;background:#C2003F;display:flex;align-items:center;justify-content:center;color:#fff;font-weight:800;font-size:15px">A</div>
    <div><div style="color:#fff;font-weight:700;font-size:15px">Ana-Bala</div><div style="font-size:11px">back office</div></div>
  </div>

  <!-- пункт активный -->
  <div style="background:#fff;color:#1E1A1D;border-radius:8px;font-weight:600;padding:8px 12px;font-size:14px;margin-top:3px;display:flex;align-items:center;gap:8px">Продажи</div>
  <!-- подпункты активного -->
  <div style="padding:6px 12px 6px 26px;font-size:13px;color:#fff;font-weight:600">Заказы</div>
  <div style="padding:6px 12px 6px 26px;font-size:13px;color:#8F868C">Магазин</div>

  <!-- пункт обычный со стрелкой -->
  <div style="padding:8px 12px;font-size:14px;margin-top:3px;display:flex;align-items:center;gap:8px">Склад<span style="margin-left:auto;color:#5A5158;font-size:11px">›</span></div>

  <!-- Экстренные: особый -->
  <div style="color:#FF6B8F;font-weight:600;padding:8px 12px;font-size:14px;margin-top:3px;display:flex;align-items:center;gap:8px">Экстренные<span style="margin-left:auto;background:#C2003F;color:#fff;border-radius:999px;padding:0 7px;font-size:11px;font-weight:700;line-height:18px">2</span></div>

  <div style="flex:1"></div>

  <!-- внешние ссылки -->
  <div style="padding:8px 12px 0;display:flex;flex-direction:column;gap:4px;font-size:12px;color:#6B6067">
    <div style="display:flex;justify-content:space-between">Лендинг<span>↗</span></div>
    <div style="display:flex;justify-content:space-between">API-сервис<span>↗</span></div>
  </div>

  <!-- пользователь -->
  <div style="border-top:1px solid #332C31;margin-top:10px;padding:11px 12px 0;display:flex;align-items:center;gap:10px">
    <div style="width:28px;height:28px;border-radius:50%;background:#3A3238;display:flex;align-items:center;justify-content:center;color:#fff;font-size:12px;font-weight:700">Н</div>
    <div style="min-width:0"><div style="color:#fff;font-size:13px;font-weight:600">Нуржан</div><div style="font-size:11px">оператор</div></div>
  </div>
  <div style="padding:9px 12px 2px;font-size:10px;color:#5A5158">v0.1.0 · not a medical device</div>
</div>
```

### Структура меню — ровно семь разделов

```
Обзор              → Сводка · Аналитика · Когорты
Экстренные         (без подпунктов, со счётчиком)
Продажи            → Заказы · Магазин · Финансы · Возвраты · Маркетинг
Склад              → Остатки · Поставки и приёмка · Каталог
Пользователи       → Мамы · Дети · Устройства · Сегменты · Поддержка
Контент            → Антенатальный уход · Календари · Вакцинация · Гиды и статьи · Аудио · Курс Ма!Ма!
Настройки          → Персонал · Безопасность · Журнал действий · Интеграции
```
Подпункты раскрываются **только у активного раздела**, у остальных — стрелка `›`. Аватар и роль в подвале меняются под экран: Нуржан (оператор), Тимур (кладовщик), Асем (контент-редактор), Диас (владелец).

## 3.3 Топбар

```html
<div style="height:56px;flex:0 0 56px;background:#fff;border-bottom:1px solid #D8D2CE;display:flex;align-items:center;padding:0 22px;gap:14px">
  <div style="font-size:18px;color:#7A7076">‹</div>            <!-- только на вложенных -->
  <div style="font-weight:700;font-size:17px">Заказы</div>
  <div style="font-size:13px;color:#7A7076">284 всего · 14 требуют ответа</div>
  <div style="margin-left:auto;display:flex;gap:8px">
    <!-- вторичная кнопка -->
    <div style="border:1px solid #D8D2CE;background:#fff;border-radius:8px;height:34px;display:flex;align-items:center;padding:0 12px;font-size:13px;font-weight:600">Выгрузить CSV</div>
    <!-- основная -->
    <div style="background:#C2003F;color:#fff;border-radius:8px;height:34px;display:flex;align-items:center;padding:0 14px;font-size:13px;font-weight:600">Новый заказ</div>
  </div>
</div>
```
Подпись рядом с заголовком — не украшение: она всегда содержит счётчик и то, что требует внимания.
**Поиск ⌘K** (только на дашборде): `flex:1;max-width:360px;background:#F4F1EE;border:1px solid #D8D2CE;border-radius:8px;height:34px` + `⌘K` моно справа.

## 3.4 Таблица

```html
<div style="background:#fff;border:1px solid #D8D2CE;border-radius:10px;overflow:hidden;display:flex;flex-direction:column;min-height:0">

  <!-- панель фильтров (опционально) -->
  <div style="padding:12px 16px;border-bottom:1px solid #EDE8E4;display:flex;gap:8px;align-items:center">
    <div style="flex:1;background:#F4F1EE;border:1px solid #D8D2CE;border-radius:8px;height:32px;display:flex;align-items:center;padding:0 12px;font-size:13px;color:#8A8085">Имя, телефон, IMEI</div>
    <div style="border:1px solid #D8D2CE;border-radius:7px;padding:6px 11px;font-size:12px;font-weight:600">Этап ▾</div>
  </div>

  <!-- шапка -->
  <div style="display:grid;grid-template-columns:74px minmax(0,1.3fr) 130px 110px 110px;padding:9px 16px;background:#FAF8F6;border-bottom:1px solid #EDE8E4;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#7A7076">
    <div>№</div><div>Клиент</div><div>Создан</div><div>Сумма</div><div>Статус</div>
  </div>

  <!-- строка -->
  <div style="display:grid;grid-template-columns:74px minmax(0,1.3fr) 130px 110px 110px;padding:10px 16px;border-bottom:1px solid #F2EEEB;font-size:13px;align-items:center">
    <div style="font-family:'JetBrains Mono',monospace;font-weight:600">4826</div>
    <div><div style="font-weight:600">Айгерим Досова</div><div style="font-size:12px;color:#7A7076">+7 707 345 22 44</div></div>
    <div style="color:#544C51;font-family:'JetBrains Mono',monospace;font-size:12px">03.08 16:12</div>
    <div style="font-weight:600">39 000 ₸</div>
    <div><span style="background:#C2003F;color:#fff;border-radius:5px;padding:3px 8px;font-size:12px;font-weight:700">Новый</span></div>
  </div>

  <div style="flex:1"></div>
  <!-- подвал -->
  <div style="border-top:1px solid #EDE8E4;background:#FAF8F6;padding:10px 16px;font-size:13px;color:#7A7076">Показано 8 из 284</div>
</div>
```

**Критично:** гибкие колонки только через `minmax(0,1fr)` — иначе длинный текст рвёт сетку. Сумма фиксированных колонок не должна превышать ширину карточки. Строка, требующая внимания, красится фоном `#FBF0F3` (срочно) или `#FDF6EA` (внимание).

Подвал таблицы всегда объясняет правило: «Удалять поставки нельзя, движения по складу остаются», «Списание без причины не проводится».

## 3.5 Статус-чипы — полный набор

```
Новый / срочно     background:#C2003F; color:#fff
Собран / внимание  background:#FDF6EA; color:#8A5A00
В пути / Kaspi / ок background:#EDF5F1; color:#1E7A54
Доставлен / архив  background:#F0EDEA; color:#544C51
Возврат / ошибка   background:#FBF0F3; color:#C2003F
Черновик           background:#F5E6C8; color:#8A5A00
Этап мамы          background:#F1ECFF; color:#4C31C4
```
Все: `border-radius:5px; padding:3px 8px; font-size:12px; font-weight:700`.

## 3.6 Карточка и метрика

```html
<div style="background:#fff;border:1px solid #D8D2CE;border-radius:10px;padding:16px">
  <div style="font-weight:700;font-size:15px">Заголовок</div>
  …
</div>

<!-- метрика: подпись → число → КОММЕНТАРИЙ (обязателен) -->
<div style="background:#fff;border:1px solid #D8D2CE;border-radius:10px;padding:14px">
  <div style="font-size:12px;color:#7A7076;font-weight:600">Брелоков</div>
  <div style="font-weight:800;font-size:26px;margin-top:4px;color:#8A5A00">26</div>
  <div style="font-size:12px;color:#7A7076">хватит на 4 дня · поставка 12</div>
</div>
```
Метрика без пояснения запрещена: «26 шт» ничего не значит, «хватит на 4 дня при поставке 12 дней» значит всё.

Ряд метрик: `display:grid;grid-template-columns:repeat(N,1fr);gap:12px`, N = 4–5.

## 3.7 Список ключ-значение

```html
<div style="display:flex;flex-direction:column;font-size:13px;margin-top:8px">
  <div style="display:flex;justify-content:space-between;gap:10px;padding:8px 0;border-bottom:1px solid #F2EEEB">
    <span style="color:#7A7076">Себестоимость шт</span><span style="font-weight:600;text-align:right">340 ₸</span>
  </div>
  <!-- у последней строки border-bottom нет -->
</div>
```

## 3.8 Полоса-показатель

```html
<div>
  <div style="display:flex;justify-content:space-between;font-size:13px"><span>Комплект</span><span style="font-weight:600">72 %</span></div>
  <div style="height:6px;background:#EDE8E4;border-radius:3px;margin-top:5px"><div style="width:72%;height:100%;background:#C2003F;border-radius:3px"></div></div>
  <div style="font-size:11.5px;color:#7A7076;margin-top:3px">маржа 65 % · и весь риск поставки</div>
</div>
```

## 3.9 Плашки-выводы (4 вида)

```
нейтральная  background:#F4F1EE; border:1px solid #EDE8E4; color:#544C51
внимание     background:#FDF6EA; border:1px solid #EBD9B8; color:#6E4A00
критичная    background:#FBF0F3; border:1px solid #E8C3CF; color:#8A1240
норма        background:#EDF5F1; border:1px solid #CFE5DA; color:#0E5F42
```
Все: `border-radius:8px; padding:10px 12px; font-size:13px; line-height:1.45`.

## 3.10 Поля формы

```html
<div style="min-width:0">
  <div style="font-size:12px;font-weight:700;text-transform:uppercase;letter-spacing:.06em;color:#7A7076">Название RU</div>
  <div style="background:#F4F1EE;border:1px solid #D8D2CE;border-radius:8px;height:38px;display:flex;align-items:center;padding:0 12px;font-size:14px;margin-top:5px">Ниблер и первые ложки</div>
</div>
<!-- textarea: min-height:52–74px; padding:10px 12px; line-height:1.5 -->
```
Два поля в ряд: `display:grid;grid-template-columns:1fr 1fr;gap:14px`.

**Сегменты выбора:**
```html
<div style="display:flex;gap:6px;margin-top:5px;flex-wrap:wrap">
  <div style="background:#1E1A1D;color:#fff;border-radius:8px;padding:8px 13px;font-size:13px;font-weight:600">CSV</div>
  <div style="border:1px solid #D8D2CE;border-radius:8px;padding:7px 13px;font-size:13px;font-weight:600">XLSX</div>
</div>
```
**Чекбокс:** `width:16px;height:16px;border-radius:4px;border:1px solid #C2003F;background:#C2003F;color:#fff` + `✓`.
**Переключатель:** `42×25`, вкл `#17A97A`, выкл `#E3D5DB`, кружок 19 px.

## 3.11 Модалка

```html
<div style="position:absolute;inset:0;background:rgba(30,20,26,.42);display:flex;align-items:center;justify-content:center;padding:40px">
  <div style="width:100%;max-width:600px;background:#fff;border:1px solid #C9C2BD;border-radius:12px;box-shadow:0 18px 44px rgba(30,20,26,.22);overflow:hidden">
    <div style="padding:16px 20px;border-bottom:1px solid #EDE8E4;display:flex;align-items:flex-start;gap:12px">
      <div style="flex:1;min-width:0"><div style="font-weight:700;font-size:17px">Добавить прививку</div><div style="font-size:13px;color:#7A7076;margin-top:3px">Публикуется новой версией календаря</div></div>
      <div style="color:#A8949F;font-size:17px">✕</div>
    </div>
    <div style="padding:16px 20px;display:flex;flex-direction:column;gap:12px">…</div>
    <div style="padding:14px 20px;border-top:1px solid #EDE8E4;background:#FAF8F6;display:flex;gap:8px;align-items:center">
      <div style="font-size:12px;color:#7A7076">Изменение затрагивает всех детей</div>
      <div style="margin-left:auto;display:flex;gap:8px">
        <div style="border:1px solid #D8D2CE;background:#fff;border-radius:8px;height:36px;display:flex;align-items:center;padding:0 14px;font-size:13px;font-weight:600">Отмена</div>
        <div style="background:#C2003F;color:#fff;border-radius:8px;height:36px;display:flex;align-items:center;padding:0 16px;font-size:13px;font-weight:600">Сохранить</div>
      </div>
    </div>
  </div>
</div>
```
Слева в подвале — **последствие действия**, не пустое место. Опасное действие: `background:#A8002F`.
Модалка в контексте: под подложкой видна размытая таблица `filter:blur(1px);opacity:.5`.

## 3.12 Галерея форм (несколько панелей на одном кадре)

```html
<div style="flex:1;min-height:0;padding:20px 22px;background:#EFEBE7;display:grid;grid-template-columns:1fr 1fr;gap:18px;align-items:start;overflow:hidden">
  <div style="display:flex;flex-direction:column;gap:18px;min-width:0">…панели левой колонки…</div>
  <div style="display:flex;flex-direction:column;gap:18px;min-width:0">…панели правой…</div>
</div>
```
**Правило, на котором легко ошибиться:** доступная высота ровно **802 px**. Сумма высот панелей в каждой колонке не должна её превышать. Панели распределяются по высоте, а не «через одну». `align-items:start` обязателен — иначе строка грида растягивается по самой высокой панели.

Панель галереи:
```html
<div style="background:#fff;border:1px solid #C9C2BD;border-radius:12px;box-shadow:0 10px 26px rgba(30,20,26,.10);overflow:hidden">
  <div style="padding:13px 16px;border-bottom:1px solid #EDE8E4"><div style="font-weight:700;font-size:15px">Заказ поставщику</div><div style="font-size:12px;color:#7A7076;margin-top:2px">Черновик ПН-124</div></div>
  <div style="padding:14px 16px;display:flex;flex-direction:column;gap:10px">…</div>
  <div style="padding:11px 16px;border-top:1px solid #EDE8E4;background:#FAF8F6;display:flex;gap:8px;align-items:center">…кнопки справа…</div>
</div>
```

## 3.13 Графики

**Столбики-стек (выручка по продуктам):** колонка `display:flex;flex-direction:column;justify-content:flex-end;gap:2px;height:100%`, сегменты в порядке брелок → часы → комплект снизу вверх.
**Спарклайн:** полоски `flex:1`, последняя `#C2003F`, прочие `#E7C8D4`.
**Тепловая карта когорт:** `grid-template-columns:110px repeat(6,1fr)`, ячейка `height:38px;border-radius:6px;background:rgba(194,0,63,α)` где α = 0.08 + v/145, текст белый при v > 65, пустая ячейка `#F7F4F2`.
**Воронка:** полосы `height:16px` разной ширины, цвет от `#1E1A1D` через `#6B6067` и `#E0A33C` к `#C2003F`.
**Коридор перцентилей:** контейнер `#FBF6F3`, зелёная зона `#DFF3EA;opacity:.7`, точки абсолютом.

## 3.14 Таймлайн (история заказа, журнал)

```html
<div style="display:flex;gap:12px">
  <div style="display:flex;flex-direction:column;align-items:center">
    <div style="width:9px;height:9px;border-radius:50%;background:#C2003F;margin-top:5px"></div>
    <div style="width:1px;flex:1;background:#E5DFDB"></div>
  </div>
  <div style="padding-bottom:14px"><div style="font-size:13px;font-weight:600">Заказ создан из WhatsApp</div><div style="font-size:12px;color:#7A7076">3 августа, 16:12 · бот</div></div>
</div>
```

## 3.15 Строчные действия в таблице

```html
<div style="display:flex;gap:6px;justify-content:flex-end">
  <div style="border:1px solid #D8D2CE;border-radius:6px;padding:4px 9px;font-size:12px;font-weight:600">Изм.</div>
  <div style="border:1px solid #D8D2CE;border-radius:6px;padding:4px 9px;font-size:12px;font-weight:600">Скрыть</div>
  <div style="border:1px solid #E8C3CF;color:#C2003F;border-radius:6px;padding:4px 9px;font-size:12px;font-weight:600">Удл.</div>
</div>
```

## 3.16 Пустые состояния и сбои

```html
<div style="background:#fff;border:1px solid #C9C2BD;border-radius:12px;padding:26px;display:flex;flex-direction:column;align-items:center;text-align:center">
  <div style="width:52px;height:52px;border-radius:16px;background:#FBF0F3;display:flex;align-items:center;justify-content:center;color:#C2003F;font-size:22px;font-weight:800">＋</div>
  <div style="font-weight:700;font-size:16px;margin-top:12px">Заказов пока нет</div>
  <div style="font-size:13px;color:#544C51;margin-top:6px;line-height:1.5;max-width:360px">Первый заказ появится, когда клиент напишет в WhatsApp или вы создадите его вручную.</div>
  <div style="display:flex;gap:8px;margin-top:14px">…кнопки…</div>
</div>
```
Шесть обязательных состояний: пусто · не найдено (с подсказкой, что убрать из фильтров) · сервер не ответил (с показом кеша и временем последних данных) · нет доступа (с объяснением, у кого спросить) · идёт операция (с процентом) · сохранено (с откатом за 5 минут).

---

# ЧАСТЬ 4 · ПОЛНЫЙ СОСТАВ КАДРОВ (76)

## Обзор

**00 · Дашборд владельца** — «Доброе утро, Диас» + дата. Четыре ряда: (1) пять метрик денег — выручка к плану, чистая прибыль, заказы, деньги в товаре, кассовый разрыв; (2) «Что горит» со счётчиком 4 + график выручки за 14 дней + «Откуда выручка»; (3) «Кто с нами» (мамы, дети, устройства, активные) + «Живо ли приложение» (удержание, зоны, курс, возвраты); (4) тёмная карточка «Решение недели» с тремя вариантами действия. Никакой кнопки «Новый заказ».

**01 · Дашборд оператора** — поиск ⌘K, кнопка «Ответить на 3 заказа · 1 ч+». Пять метрик → график выручки + «Требует внимания» → таблица последних заказов.

**20 · Аналитика** — воронка лендинг → магазин → WhatsApp → заказ, метрики продукта, причины возвратов.
**20a · Когорты** — тепловая карта удержания по месяцам покупки + «Что удерживает» + вывод.

**19 · Экстренные** — метрики (активных, за сутки, ложных 61 %, реакция 1:40) → таблица событий → карточка SOS с картой и «Позвонить маме» → инструкция оператора 4 шага → плашка «Мы не служба спасения».

## Продажи

**02 · Заказы** — фильтры-чипы по статусам со счётчиками → таблица 9 колонок с чекбоксами → подвал массовых действий.
**02a · Формы создания** · **02b · Выгрузить CSV** (модалка с выбором колонок и предупреждением про персональные данные) · **02c · Поиск, фильтры, массовые действия** (4 панели) · **02d · Подтверждение и результат** · **02e · Пустые состояния и сбои**.
**03 · Карточка заказа** — топбар со статусом и «Подтвердить и собрать». Слева: состав, резерв с серийниками, история. Справа: клиент с WhatsApp, доставка, оплата, комментарий оператора, опасные действия.
**04 · Магазин** — метрики витрины и лидов → таблица лидов (без ответа наверху) → панель витрины → объяснение «почему без корзины».
**05 · Финансы · платежи** · **05a · Возвраты и брак** · **05b · Отчёт**.
**06 · Маркетинг** — таблица промокодов → конструктор рассылки с сегментом и правилом «не чаще раза в неделю».

## Склад

**07 · Остатки** — янтарная плашка дефицита → таблица с колонкой «Хватит на» → движения за день → поставки в пути.
**07a · Поставки** — таблица ПН со статусами → карточка ждущей приёмки.
**07b · Формы создания** — заказ поставщику, приход без заказа, добавить поставщика, добавить категорию.
**07c · Приёмка со сканером** — тёмная полоса сканера → таблица «ожидали / принято / брак / расхождение» → блок расхождения с претензией → размещение по ячейкам → партия → «Оприходовать 456 шт».
**07d · Сборка и отгрузка** · **07e · Завершение процессов** (4 панели) · **07f · Ячейки и инвентаризация** · **07g · Поставщики**.

## Каталог

**08 · Товары** — слева категории и **этапы мамы**, справа таблица с колонкой этапа → массовые действия.
**08a · Карточка товара** — вкладки (Основное, Фото, Склад, **Персонализация**, SEO) → поля RU/ҚАЗ → блок персонализации с диапазоном возраста ребёнка и охватом → справа фото, склад, история изменений, «В архив».
**08b · Категории и этапы** · **08c · Диалоги** (6 модалок) · **08d · Печать, импорт, массовое**.

## Пользователи

**09 · Мамы** — таблица с этапом, детьми, устройствами, курсом, активностью → распределение по этапам → массовые действия → плашка про удаление аккаунта.
**09a · Карточка мамы** — дети, устройства с серийниками и «Отвязать», заказы; справа этап, курс, приложение, опасные действия.
**09b · Сегменты** — таблица сегментов (живые и замороженные) → конструктор → правило «нельзя строить по здоровью».
**10 · Дети** · **10a · Добавить ребёнка** · **11 · Устройства** (метрики онлайн, таблица с прошивками, «Пометить браком») · **12 · Поддержка** (обращения, карточка с историей устройства, шаблоны, «Ответить в WhatsApp»).

## Контент

**13 · Антенатальный уход** — метрики (беременных, просрочен скрининг, высокий риск, учёт до 12 недель) → таблица «кто требует внимания» → график по протоколу РК → красные флаги.
**14 · Календари** → **14a · 40 недель** (метрики заполненности, таблица недель с фото и языками) → **14b · Редактор недели** (фото плода, поля RU/ҚАЗ, нормы и красные флаги, «кого затрагивает 312 мам») → **14c · Развитие по месяцам** (сетка 36, навыки с порядком) → **14d · Цикл** (фазы с цветами, справочник симптомов, правила прогноза, переходы между календарями) → **14e · Формы создания**.
**15 · Вакцинация** — таблица нацкалендаря с охватом → провал по пневмококку 76 % с объяснением → настройки напоминаний → версии.
**15a · Добавить прививку** · **15b · История версий** (черновик + версии с diff, влияние на 6 104 детей).
**16 · Гиды и статьи** · **16a · Новая статья** (RU/ҚАЗ, блок «Красный флаг», запрет публикации без проверки врачом) · **16b · Экстренная помощь**.
**17 · Аудио** — метрики (записей, 12 из 64 на казахском, дней без записи) → таблица → расписание.
**17a · Расписание** (календарь 21 день, пустые дни жёлтым, правило «три пустых дня отключают блок») · **17b · Загрузить запись** (волна с обрезкой тишины, чек-лист перед публикацией, превью «как увидит мама») · **17c · Детектор плача** (точность по причинам, «послушать запись нельзя — модель на телефоне», порог 45 %).
**18 · Курс · уроки** · **18a · Структура модулей** (drag-порядок, досматриваемость, проблемные уроки, доступы).

## Система

**21 · Отправки и публикации** — 4 панели с последствиями.
**22 · Безопасность** — метрики просмотров защищённых данных → журнал доступа с основанием → кто что видит → хранение → открытый вопрос.
**23 · Персонал и журнал** — таблица сотрудников → права роли → журнал действий (просмотр здоровья подсвечен).
**23a · Роли и права** — матрица 18 разрешений × 5 ролей, строки здоровья и геолокации подсвечены `#FBF0F3`.
**24 · Интеграции** · **24a · Настроить** (ключ как `••••7f2a`, шаблоны, доставляемость, расход) · **24b · Проверить связь** (пошаговая диагностика, перевыпуск ключа, резервный шлюз).
**25 · Уведомления** · **26 · Настройки** (языки, поведение приложения, медицинские оговорки, опасная зона) · **26a · Справочники и правила** · **26b · Служебные страницы**.
**27 · Карта действий** — таблица на 25 кнопок: экран, кнопка, тип реакции, что открывается. Плюс правило выбора типа.

---

# ЧАСТЬ 5 · ПРАВИЛА ПОВЕДЕНИЯ

1. **Ничего не удаляется.** Товар с историей → архив. Отменённый заказ — статус. Журнал не редактируется, хранится 3 года. Полное удаление только у сущностей без истории (неопубликованный урок, черновик).
2. **Модалка или страница.** Модалка — короткое действие с возвратом. Страница — работа дольше минуты (приёмка, редактор, расписание). Подтверждение — необратимое или затрагивающее многих. Полная карта — кадр 27.
3. **Приёмка принимает факт, а не накладную.** Расхождение → претензия поставщику, себестоимость пересчитывается с учётом брака.
4. **Двуязычность блокирует публикацию.** Без казахской версии кнопка «Опубликовать» неактивна. Медицинский текст — только после проверки врачом.
5. **Здоровье и геолокация — только владелец,** каждый просмотр в журнале с причиной. Сегменты по здоровью строить нельзя.
6. **Два дашборда не смешивать:** владельцу — деньги и решения, оператору — очереди.
7. **Каждая метрика с пояснением,** каждый подвал таблицы — с правилом.
8. **Ролей пять:** Владелец (всё, с журналом) · Оператор (заказы, клиенты, поддержка, экстренные) · Продавец (заказы, витрина, остатки, контакты — без маржи и детей) · Кладовщик (склад) · Контент-редактор (контент; описания товаров без цен). Новая роль наследует минимум и добирает права поштучно.

---

# ЧАСТЬ 6 · ЧЕК-ЛИСТ

- [ ] 1440 × 900 — ни один блок не обрезан; колонки галерей проверены по сумме высот (≤ 802 px)
- [ ] Гибкие колонки таблиц в `minmax(0,1fr)`; сумма фиксированных ≤ ширины карточки
- [ ] `min-width:0` на контентной области, `min-height:0` на flex-контейнерах
- [ ] `tabular-nums` включён, цифры выровнены
- [ ] Моно-шрифт на всех идентификаторах и времени
- [ ] Малиновый только на действии и просрочке; строка красится фоном, не текстом
- [ ] У каждой метрики есть поясняющая строка
- [ ] Подвал каждой таблицы содержит правило
- [ ] Необратимые действия — через подтверждение с последствием в подвале модалки
- [ ] Подпункты раскрыты только у активного раздела меню
