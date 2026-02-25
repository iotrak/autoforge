const PopoverGroupHook = {
  mounted() {
    this.observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (
          mutation.type === "attributes" &&
          mutation.attributeName === "hidden" &&
          !mutation.target.hidden
        ) {
          // A popover just became visible — hide all others
          const allPopovers = this.el.querySelectorAll('[data-part="popover"]');
          for (const popover of allPopovers) {
            if (popover !== mutation.target && !popover.hidden) {
              popover.hidden = true;
            }
          }
          break;
        }
      }
    });

    this.observer.observe(this.el, {
      attributes: true,
      attributeFilter: ["hidden"],
      subtree: true,
    });
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
    }
  },
};

export default PopoverGroupHook;
