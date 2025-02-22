// Function to handle eye movement
function moveEyes(x, y) {
  const pupils = document.querySelectorAll(".eyes");
  pupils.forEach((pupil) => {
    const eye = pupil.parentElement;
    const rect = eye.getBoundingClientRect();

    // Calculate center position of the eye
    const eyeCenterX = rect.left + rect.width / 2;
    const eyeCenterY = rect.top + rect.height / 2;

    // Calculate angle towards pointer position
    const angle = Math.atan2(y - eyeCenterY, x - eyeCenterX);

    // Calculate pupil's new position
    const pupilRadius = (rect.width / 2) * 0.8;
    const pupilX = Math.cos(angle) * pupilRadius;
    const pupilY = Math.sin(angle) * pupilRadius;

    // Move the pupil
    pupil.style.transform = `translate(${pupilX}px, ${pupilY}px)`;
  });
}

// Function to check if touch is on an eye element
function isTouchingEye(touch) {
  const element = document.elementFromPoint(touch.clientX, touch.clientY);
  return (
    element &&
    (element.classList.contains("eyes") ||
      element.contains(document.querySelector(".eyes")))
  );
}

// Keep track of the last known pointer position
let lastPointerX = window.innerWidth / 2;
let lastPointerY = window.innerHeight / 2;

// Update last known position on mouse move
document.addEventListener("mousemove", (event) => {
  lastPointerX = event.clientX;
  lastPointerY = event.clientY;
  moveEyes(lastPointerX, lastPointerY);
});

// Touch move event listener
document.addEventListener(
  "touchmove",
  (event) => {
    const touch = event.touches[0];

    // Only prevent default if touching the eyes
    if (isTouchingEye(touch)) {
      event.preventDefault();
    }

    lastPointerX = touch.clientX;
    lastPointerY = touch.clientY;
    moveEyes(lastPointerX, lastPointerY);
  },
  { passive: false }
);

// Touch start event listener
document.addEventListener("touchstart", (event) => {
  const touch = event.touches[0];
  lastPointerX = touch.clientX;
  lastPointerY = touch.clientY;
  moveEyes(lastPointerX, lastPointerY);
});

// Scroll event listener
let ticking = false;
document.addEventListener("scroll", () => {
  if (!ticking) {
    window.requestAnimationFrame(() => {
      moveEyes(lastPointerX + window.scrollX, lastPointerY + window.scrollY);
      ticking = false;
    });
    ticking = true;
  }
});

// Handle window resize
window.addEventListener("resize", () => {
  lastPointerX = window.innerWidth / 2;
  lastPointerY = window.innerHeight / 2;
  moveEyes(lastPointerX, lastPointerY);
});

const menuButton = document.getElementById("menuButton");
const dropdownMenu = document.getElementById("dropdownMenu");
var isOpen = false;

const toggleMenu = (open) => {
  isOpen = open;
  menuButton.setAttribute("aria-expanded", open);

  if (open) {
    dropdownMenu.classList.remove("hidden");
    document.body.classList.add("blur-active");
    requestAnimationFrame(() => {
      dropdownMenu.classList.remove("opacity-0");
    });
    menuButton.style.transform = "rotate(45deg)";
  } else {
    dropdownMenu.classList.add("opacity-0");
    document.body.classList.remove("blur-active");
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
const header = document.querySelector(".header-container");

window.addEventListener("scroll", () => {
  if (window.scrollY > 10) {
    header.classList.add("scrolled");
  } else {
    header.classList.remove("scrolled");
  }
});
