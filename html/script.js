function post(endpoint, body) {
    return fetch(`https://${GetParentResourceName()}/${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(body || {}),
    }).catch((error) => console.error(`[rsg-goldclaim] request to ${endpoint} failed:`, error));
}

function showApp() {
    document.getElementById('app').classList.remove('hidden');
}

function hideAppIfAllClosed() {
    const anyVisible = ['context-panel', 'modal-overlay', 'missing-items-overlay', 'progress-overlay', 'crafting-panel']
        .some((id) => !document.getElementById(id).classList.contains('hidden'));
    if (!anyVisible) {
        document.getElementById('app').classList.add('hidden');
    }
}

function statClassFor(colorScheme, percent) {
    if (colorScheme === 'green') {
        if (percent >= 60) return 'stat-good';
        if (percent >= 30) return 'stat-warn';
        return 'stat-bad';
    }
    if (colorScheme === 'blue' || colorScheme === 'orange') return 'stat-warn';
    return 'stat-good';
}

/* ============================================================ */
/* context menu                                                  */
/* ============================================================ */
const contextPanel = document.getElementById('context-panel');
const contextTitle = document.getElementById('context-title');
const contextSubtitle = document.getElementById('context-subtitle');
const contextBackBtn = document.getElementById('context-back');
const contextCloseBtn = document.getElementById('context-close');
const contextOptions = document.getElementById('context-options');

function renderContext(data) {
    showApp();
    contextPanel.classList.remove('hidden');

    contextTitle.textContent = data.title || '';
    contextSubtitle.textContent = data.subtitle || '';
    contextSubtitle.classList.toggle('hidden', !data.subtitle);
    contextBackBtn.classList.toggle('hidden', !data.canGoBack);

    contextOptions.innerHTML = '';

    (data.options || []).forEach((option, index) => {
        const row = document.createElement('div');
        const isStatic = !option.event;
        row.className = 'option-row' + (option.disabled ? ' option-row-disabled' : '') + (isStatic ? ' option-row-static' : '');

        if (option.icon) {
            const icon = document.createElement('div');
            icon.className = 'option-icon';
            const i = document.createElement('i');
            i.className = option.icon;
            icon.appendChild(i);
            row.appendChild(icon);
        }

        const body = document.createElement('div');
        body.className = 'option-body';

        const titleRow = document.createElement('div');
        titleRow.className = 'option-title-row';

        const title = document.createElement('span');
        title.className = 'option-title';
        title.textContent = option.title || '';
        titleRow.appendChild(title);

        if (option.badge) {
            const badge = document.createElement('span');
            badge.className = 'option-badge';
            badge.textContent = option.badge;
            titleRow.appendChild(badge);
        }

        body.appendChild(titleRow);

        if (option.description) {
            const desc = document.createElement('div');
            desc.className = 'option-desc';
            desc.textContent = option.description;
            body.appendChild(desc);
        }

        if (typeof option.progress === 'number') {
            const track = document.createElement('div');
            track.className = 'stat-bar-track';
            const fill = document.createElement('div');
            const percent = Math.max(0, Math.min(100, option.progress));
            fill.className = 'stat-bar-fill ' + statClassFor(option.colorScheme, percent);
            fill.style.width = percent + '%';
            track.appendChild(fill);
            body.appendChild(track);
        }

        row.appendChild(body);

        if (option.arrow) {
            const arrow = document.createElement('i');
            arrow.className = 'fa-solid fa-chevron-right option-arrow';
            row.appendChild(arrow);
        }

        if (!isStatic && !option.disabled) {
            row.addEventListener('click', () => post('contextSelect', { index }));
        }

        contextOptions.appendChild(row);
    });
}

function closeContextPanel() {
    contextPanel.classList.add('hidden');
    hideAppIfAllClosed();
}

contextBackBtn.addEventListener('click', () => post('contextBack'));
contextCloseBtn.addEventListener('click', () => {
    post('contextClose');
    closeContextPanel();
});

/* ============================================================ */
/* input modal (Lua-driven: OpenInputDialog)                     */
/* ============================================================ */
const modalOverlay = document.getElementById('modal-overlay');
const modalTitle = document.getElementById('modal-title');
const modalFields = document.getElementById('modal-fields');
const modalActions = document.getElementById('modal-actions');

function renderModal(data) {
    showApp();
    modalOverlay.classList.remove('hidden');
    modalTitle.textContent = data.title || '';
    modalFields.innerHTML = '';
    modalActions.innerHTML = '';

    const fields = data.fields || [];
    const inputs = [];

    fields.forEach((field, index) => {
        if (field.type === 'confirm') {
            const wrap = document.createElement('div');

            if (field.label) {
                const label = document.createElement('span');
                label.className = 'modal-field-label';
                label.textContent = field.label;
                wrap.appendChild(label);
            }
            if (field.description) {
                const desc = document.createElement('span');
                desc.className = 'modal-field-desc';
                desc.textContent = field.description;
                wrap.appendChild(desc);
            }

            modalFields.appendChild(wrap);
            inputs.push({ type: 'confirm' });
            return;
        }

        const wrap = document.createElement('div');

        if (field.label) {
            const label = document.createElement('label');
            label.className = 'modal-field-label';
            label.textContent = field.label;
            wrap.appendChild(label);
        }

        if (field.description) {
            const desc = document.createElement('span');
            desc.className = 'modal-field-desc';
            desc.textContent = field.description;
            wrap.appendChild(desc);
        }

        let control;
        if (field.type === 'select') {
            control = document.createElement('select');
            control.className = 'modal-select';
            if (field.required) {
                const placeholder = document.createElement('option');
                placeholder.value = '';
                placeholder.textContent = 'Select...';
                placeholder.disabled = true;
                placeholder.selected = true;
                control.appendChild(placeholder);
            }
            (field.options || []).forEach((opt) => {
                const optionEl = document.createElement('option');
                optionEl.value = opt.value;
                optionEl.textContent = opt.label;
                control.appendChild(optionEl);
            });
        } else {
            control = document.createElement('input');
            control.className = 'modal-input';
            control.type = 'text';
        }

        wrap.appendChild(control);
        modalFields.appendChild(wrap);
        inputs.push({ type: field.type, el: control, required: !!field.required });
    });

    if (fields.length === 0) {
        modalActions.classList.add('center');
        const closeBtn = document.createElement('button');
        closeBtn.className = 'wood-btn';
        closeBtn.textContent = 'Close';
        closeBtn.addEventListener('click', submitCancel);
        modalActions.appendChild(closeBtn);
        return;
    }

    modalActions.classList.remove('center');

    const cancelBtn = document.createElement('button');
    cancelBtn.className = 'wood-btn wood-btn-muted';
    cancelBtn.textContent = 'Cancel';
    cancelBtn.addEventListener('click', submitCancel);

    const confirmBtn = document.createElement('button');
    confirmBtn.className = 'wood-btn';
    confirmBtn.textContent = 'Confirm';
    confirmBtn.addEventListener('click', () => {
        const values = [];
        for (const input of inputs) {
            if (input.type === 'confirm') continue;
            const value = input.el.value;
            if (input.required && !value) {
                input.el.focus();
                return;
            }
            values.push(value);
        }
        submitModal(values);
    });

    modalActions.appendChild(cancelBtn);
    modalActions.appendChild(confirmBtn);
}

function submitModal(values) {
    modalOverlay.classList.add('hidden');
    hideAppIfAllClosed();
    post('modalSubmit', { values });
}

function submitCancel() {
    modalOverlay.classList.add('hidden');
    hideAppIfAllClosed();
    post('modalCancel');
}

/* ============================================================ */
/* alert modal (Lua-driven: OpenAlertDialog)                     */
/* ============================================================ */
function renderAlert(data) {
    showApp();
    modalOverlay.classList.remove('hidden');
    modalTitle.textContent = data.title || '';
    modalFields.innerHTML = '';
    modalActions.innerHTML = '';
    modalActions.classList.add('center');

    (data.lines || []).forEach((line) => {
        const row = document.createElement('div');
        row.className = 'modal-line';
        row.textContent = line;
        modalFields.appendChild(row);
    });

    const closeBtn = document.createElement('button');
    closeBtn.className = 'wood-btn';
    closeBtn.textContent = 'Close';
    closeBtn.addEventListener('click', () => {
        modalOverlay.classList.add('hidden');
        hideAppIfAllClosed();
        post('alertClose');
    });
    modalActions.appendChild(closeBtn);
}

/* ============================================================ */
/* smelter: crafting panel                                       */
/* ============================================================ */
let RSGCore = null;
let craftingData = { crafting: [] };
let playerInventory = {};
let activeCategory = null;
let selectedItem = null;
let lang = {};

const craftingPanel = document.getElementById('crafting-panel');
const categoryList = document.getElementById('categoryList');
const itemGrid = document.getElementById('itemGrid');
const itemDetails = document.getElementById('itemDetails');
const closeButton = document.getElementById('closeButton');

function getItemImagePath(itemName) {
    return `nui://rsg-inventory/html/images/${itemName}.png`;
}

function renderCategories() {
    categoryList.innerHTML = '';
    const categories = [...new Set(craftingData.crafting.map((item) => item.category))];

    categories.forEach((category) => {
        const button = document.createElement('button');
        button.className = 'category-button' + (activeCategory === category ? ' active' : '');
        button.textContent = category;
        button.addEventListener('click', () => setActiveCategory(category));
        categoryList.appendChild(button);
    });
}

function renderItems() {
    itemGrid.innerHTML = '';
    const items = craftingData.crafting.filter((item) => !activeCategory || item.category === activeCategory);

    items.forEach((item) => {
        const card = document.createElement('div');
        card.className = 'item-card' + (selectedItem && selectedItem.title === item.title ? ' selected' : '');
        card.addEventListener('click', () => setSelectedItem(item));

        const img = document.createElement('img');
        img.src = getItemImagePath(item.receive);
        img.onerror = function () { this.style.display = 'none'; };
        img.alt = item.title || 'Item';
        img.className = 'item-image';

        const title = document.createElement('h3');
        title.textContent = item.title || 'Unknown Item';

        card.appendChild(img);
        card.appendChild(title);
        itemGrid.appendChild(card);
    });
}

function renderItemDetails() {
    itemDetails.innerHTML = '';

    if (!selectedItem) {
        const message = document.createElement('p');
        message.className = 'empty-state';
        message.textContent = lang.select_item_to_view_details || 'Select an item to view details';
        itemDetails.appendChild(message);
        return;
    }

    const title = document.createElement('h3');
    title.textContent = selectedItem.title || 'Unknown Item';
    itemDetails.appendChild(title);

    const img = document.createElement('img');
    img.src = getItemImagePath(selectedItem.receive);
    img.onerror = function () { this.style.display = 'none'; };
    img.alt = selectedItem.title || 'Item';
    img.className = 'item-image';
    itemDetails.appendChild(img);

    const quantityRow = document.createElement('div');
    quantityRow.className = 'quantity-row';

    const quantityLabel = document.createElement('label');
    quantityLabel.textContent = 'Qty';
    quantityLabel.setAttribute('for', 'craft-quantity');

    const quantityInput = document.createElement('input');
    quantityInput.type = 'number';
    quantityInput.id = 'craft-quantity';
    quantityInput.min = 1;
    quantityInput.value = 1;

    quantityRow.appendChild(quantityLabel);
    quantityRow.appendChild(quantityInput);

    const actionButton = document.createElement('button');
    actionButton.className = 'wood-btn';
    actionButton.textContent = lang.craft || 'Smelt';
    actionButton.addEventListener('click', () => handleCraft(selectedItem, parseInt(quantityInput.value, 10) || 1));
    quantityRow.appendChild(actionButton);

    itemDetails.appendChild(quantityRow);

    quantityInput.addEventListener('input', () => {
        post('quantityChanged', {
            recipeKey: selectedItem.key || selectedItem.title,
            quantity: parseInt(quantityInput.value, 10) || 1,
        });
    });

    const ingredientTitle = document.createElement('h4');
    ingredientTitle.textContent = lang.required_items || 'Required Materials';
    itemDetails.appendChild(ingredientTitle);

    const ingredientList = document.createElement('ul');
    ingredientList.className = 'ingredient-list';
    ingredientList.id = 'ingredient-list';

    if (Array.isArray(selectedItem.ingredients)) {
        selectedItem.ingredients.forEach((ingredient) => {
            ingredientList.appendChild(buildIngredientRow(ingredient));
        });
    }

    itemDetails.appendChild(ingredientList);
}

function buildIngredientRow(ingredient) {
    const li = document.createElement('li');
    li.className = 'ingredient-item';

    const img = document.createElement('img');
    img.src = getItemImagePath(ingredient.item);
    img.onerror = function () { this.style.display = 'none'; };
    img.alt = ingredient.item || 'Item';
    img.className = 'ingredient-image';

    const span = document.createElement('span');
    const itemLabel = (RSGCore && RSGCore.Shared && RSGCore.Shared.Items && RSGCore.Shared.Items[ingredient.item] && RSGCore.Shared.Items[ingredient.item].label) || ingredient.item || 'Unknown';
    const playerItemCount = playerInventory[ingredient.item] || 0;
    const hasEnough = playerItemCount >= ingredient.amount;

    span.textContent = `${itemLabel}: ${ingredient.amount} ${lang.needed || 'needed'} / ${playerItemCount} ${lang.you_have || 'you have'}`;
    span.className = hasEnough ? 'text-ok' : 'text-bad';

    li.appendChild(img);
    li.appendChild(span);
    return li;
}

function setActiveCategory(category) {
    activeCategory = category;
    selectedItem = null;
    renderCategories();
    renderItems();
    renderItemDetails();
}

function setSelectedItem(item) {
    selectedItem = item;
    renderItems();
    renderItemDetails();
}

function handleCraft(item, quantity) {
    post('startCrafting', {
        recipeKey: item.key,
        actionType: lang.crafting || 'Smelting',
        name: item.title,
        receive: item.receive,
        ingredients: item.ingredients,
        giveamount: quantity,
        crafttime: item.crafttime,
    });
}

function openCraftingPanel(data) {
    showApp();
    craftingPanel.classList.remove('hidden');

    playerInventory = data.inventory || {};
    craftingData = { crafting: data.crafting || [] };
    lang = data.lang || {};

    const categories = [...new Set(craftingData.crafting.map((item) => item.category))];
    if (categories.length > 0 && !activeCategory) {
        activeCategory = categories[0];
    }

    renderCategories();
    renderItems();
    renderItemDetails();

    document.getElementById('itemsTitle').textContent = lang.craftable_items || 'Smeltable Items';
    document.getElementById('detailsTitle').textContent = lang.item_details || 'Item Details';
}

function closeCraftingPanel() {
    craftingPanel.classList.add('hidden');
    hideAppIfAllClosed();
    post('closeCrafting');
}

closeButton.addEventListener('click', closeCraftingPanel);

/* ---- missing items alert ---- */
const missingItemsOverlay = document.getElementById('missing-items-overlay');
const missingItemsList = document.getElementById('missing-items-list');

function showMissingItems(missingItems) {
    showApp();
    missingItemsList.innerHTML = '';

    (missingItems || []).forEach((item) => {
        const row = document.createElement('div');
        row.className = 'modal-line';

        const name = document.createElement('span');
        name.textContent = item.item;

        const count = document.createElement('span');
        count.className = 'text-bad';
        count.textContent = `${item.have}/${item.required}`;

        row.appendChild(name);
        row.appendChild(count);
        missingItemsList.appendChild(row);
    });

    missingItemsOverlay.classList.remove('hidden');
}

document.getElementById('missing-items-close').addEventListener('click', () => {
    missingItemsOverlay.classList.add('hidden');
    hideAppIfAllClosed();
});

/* ---- crafting progress ---- */
const progressOverlay = document.getElementById('progress-overlay');
const progressTitle = document.getElementById('progress-title');
const progressFill = document.getElementById('progress-fill');
const progressCancelBtn = document.getElementById('progress-cancel');
let progressInterval = null;
let currentProgress = 0;

function startProgressBar(duration, actionType) {
    showApp();
    progressOverlay.classList.remove('hidden');
    progressTitle.textContent = `${actionType || 'Working'}...`;
    progressFill.style.width = '0%';
    progressCancelBtn.classList.remove('hidden');

    currentProgress = 0;
    if (progressInterval) clearInterval(progressInterval);

    progressInterval = setInterval(() => {
        currentProgress += 100 / (duration / 1000);
        if (currentProgress >= 100) {
            currentProgress = 100;
            clearInterval(progressInterval);
            progressOverlay.classList.add('hidden');
            hideAppIfAllClosed();
        }
        progressFill.style.width = `${currentProgress}%`;

        if (currentProgress >= 80) {
            progressCancelBtn.classList.add('hidden');
        }
    }, 1000);
}

progressCancelBtn.addEventListener('click', () => {
    if (currentProgress < 80) {
        clearInterval(progressInterval);
        progressOverlay.classList.add('hidden');
        hideAppIfAllClosed();
        post('cancelCrafting');
    }
});

/* ============================================================ */
/* global escape key + message routing                           */
/* ============================================================ */
document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;

    if (!contextPanel.classList.contains('hidden')) {
        post('contextClose');
        closeContextPanel();
    } else if (!modalOverlay.classList.contains('hidden')) {
        submitCancel();
    } else if (!craftingPanel.classList.contains('hidden')) {
        closeCraftingPanel();
    } else if (!missingItemsOverlay.classList.contains('hidden')) {
        missingItemsOverlay.classList.add('hidden');
        hideAppIfAllClosed();
    }
});

window.addEventListener('message', (event) => {
    const data = event.data || {};

    switch (data.action) {
        case 'openContext':
            renderContext(data);
            break;
        case 'closeContext':
            closeContextPanel();
            break;
        case 'openModal':
            renderModal(data);
            break;
        case 'openAlert':
            renderAlert(data);
            break;
        case 'openCrafting':
            openCraftingPanel(data);
            break;
        case 'showMissingItems':
            showMissingItems(data.missingItems);
            break;
        case 'startProgress':
            startProgressBar(data.duration, data.actionType);
            break;
        case 'updateIngredients': {
            const list = document.getElementById('ingredient-list');
            if (list) {
                list.innerHTML = '';
                (data.ingredients || []).forEach((ingredient) => {
                    list.appendChild(buildIngredientRow(ingredient));
                });
            }
            break;
        }
        default:
            break;
    }
});
