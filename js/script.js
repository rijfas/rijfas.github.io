const menuButton = document.getElementById("menuButton");
const dropdownMenu = document.getElementById("dropdownMenu");
const blurContent = document.getElementById("blurContent");
var isOpen = false;

const toggleMenu = (open) => {
  isOpen = open;
  menuButton.setAttribute("aria-expanded", open);

  if (open) {
    dropdownMenu.classList.remove("hidden");
    blurContent.classList.add("blur-active");
    requestAnimationFrame(() => {
      dropdownMenu.classList.remove("opacity-0");
    });
    menuButton.style.transform = "rotate(45deg)";
  } else {
    dropdownMenu.classList.add("opacity-0");
    blurContent.classList.remove("blur-active");
    menuButton.style.transform = "rotate(0deg)";
    setTimeout(() => {
      dropdownMenu.classList.add("hidden");
    }, 300);
  }
};

menuButton.addEventListener("click", (e) => {
  e.stopPropagation();
  toggleMenu(!isOpen);
});

document.addEventListener("click", (event) => {
  if (
    !menuButton.contains(event.target) &&
    !dropdownMenu.contains(event.target) &&
    isOpen
  ) {
    toggleMenu(false);
  }
});
