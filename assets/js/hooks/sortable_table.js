const SortableTableHook = {
  mounted() {
    this.sortCol = null;
    this.sortDir = "asc";

    this.el.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-sort-col]");
      if (!btn) return;

      const col = btn.dataset.sortCol;
      if (this.sortCol === col) {
        this.sortDir = this.sortDir === "asc" ? "desc" : "asc";
      } else {
        this.sortCol = col;
        this.sortDir = "asc";
      }

      this.sortRows();
      this.updateIndicators();
    });
  },

  sortRows() {
    const tbody = this.el.querySelector("tbody");
    if (!tbody) return;

    const rows = Array.from(tbody.querySelectorAll("tr"));
    const col = this.sortCol;
    const dir = this.sortDir;

    rows.sort((a, b) => {
      const aVal = a.dataset[`sort${capitalize(col)}`] ?? "";
      const bVal = b.dataset[`sort${capitalize(col)}`] ?? "";

      const aNum = Number(aVal);
      const bNum = Number(bVal);
      const numeric = !isNaN(aNum) && !isNaN(bNum) && aVal !== "" && bVal !== "";

      let cmp;
      if (numeric) {
        cmp = aNum - bNum;
      } else {
        cmp = aVal.localeCompare(bVal);
      }

      return dir === "asc" ? cmp : -cmp;
    });

    for (const row of rows) {
      tbody.appendChild(row);
    }
  },

  updateIndicators() {
    for (const btn of this.el.querySelectorAll("[data-sort-col]")) {
      const indicator = btn.querySelector(".sort-indicator");
      if (!indicator) continue;

      if (btn.dataset.sortCol === this.sortCol) {
        const icon = this.sortDir === "asc" ? "hero-chevron-up" : "hero-chevron-down";
        indicator.innerHTML = `<span class="w-3 h-3 ${icon}"></span>`;
      } else {
        indicator.innerHTML = `<span class="w-3 h-3 hero-chevron-up-down opacity-0 group-hover:opacity-40 transition-opacity"></span>`;
      }
    }
  },
};

// Convert "input_cost" → "sortInput_cost" for dataset access
function capitalize(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

export default SortableTableHook;
