// Function to handle eye movement
// Function to check if device is mobile
function isMobile() {
  return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(
    navigator.userAgent
  );
}

// Function to handle eye movement
function moveEyes(x, y) {
  const pupils = document.querySelectorAll(".eyes");
  pupils.forEach((pupil) => {
    const eye = pupil.parentElement;
    const rect = eye.getBoundingClientRect();

    // Calculate center position of the eye
    const eyeCenterX = rect.left + rect.width / 2;
    const eyeCenterY = rect.top + rect.height / 2;

    // Calculate angle towards position
    const angle = Math.atan2(y - eyeCenterY, x - eyeCenterX);

    // Calculate pupil's new position
    const pupilRadius = (rect.width / 2) * 0.8;
    const pupilX = Math.cos(angle) * pupilRadius;
    const pupilY = Math.sin(angle) * pupilRadius;

    // Move the pupil
    pupil.style.transform = `translate(${pupilX}px, ${pupilY}px)`;
  });
}

// Function to move eyes randomly
function moveEyesRandomly() {
  const x = Math.random() * window.innerWidth;
  const y = Math.random() * window.innerHeight;
  moveEyes(x, y);
}

// Function to setup eyelids
function setupEyelids() {
  const eyes = document.querySelectorAll(".eyes");
  eyes.forEach((eye) => {
    const parent = eye.parentElement;

    if (!parent.querySelector(".eyelid")) {
      const eyelid = document.createElement("div");
      eyelid.className = "eyelid";

      eyelid.style.position = "absolute";
      eyelid.style.top = "-100%";
      eyelid.style.left = "0";
      eyelid.style.width = "100%";
      eyelid.style.height = "100%";
      eyelid.style.backgroundColor = "black";
      eyelid.style.transition = "top 0.15s ease-in-out";

      parent.style.position = "relative";
      parent.style.overflow = "hidden";

      parent.appendChild(eyelid);
    }
  });
}

// Function to make eyes blink
function blink() {
  const eyelids = document.querySelectorAll(".eyelid");

  eyelids.forEach((eyelid) => {
    eyelid.style.top = "0";
  });

  setTimeout(() => {
    eyelids.forEach((eyelid) => {
      eyelid.style.top = "-100%";
    });
  }, 200);
}

// Function to trigger random blinks
function startRandomBlinking() {
  function getRandomInterval() {
    return Math.random() * (6000 - 2000) + 2000;
  }

  function scheduleNextBlink() {
    setTimeout(() => {
      blink();
      scheduleNextBlink();
    }, getRandomInterval());
  }

  scheduleNextBlink();
}

// Setup random movement for mobile
function startRandomMovement() {
  function getRandomInterval() {
    // Random interval between 1 and 3 seconds
    return Math.random() * (3000 - 1000) + 1000;
  }

  function scheduleNextMovement() {
    setTimeout(() => {
      moveEyesRandomly();
      scheduleNextMovement();
    }, getRandomInterval());
  }

  scheduleNextMovement();
}

// Keep track of the last known pointer position
let lastPointerX = window.innerWidth / 2;
let lastPointerY = window.innerHeight / 2;

// Initialize device-specific behavior
function initializeEyeBehavior() {
  if (isMobile()) {
    // Mobile behavior: random movement
    startRandomMovement();

    // Remove mouse tracking events if they exist
    document.removeEventListener("mousemove", handleMouseMove);
  } else {
    // Desktop behavior: cursor tracking
    document.addEventListener("mousemove", handleMouseMove);
  }
}

// Mouse move handler
function handleMouseMove(event) {
  lastPointerX = event.clientX;
  lastPointerY = event.clientY;
  moveEyes(lastPointerX, lastPointerY);
}

// Handle window resize
window.addEventListener("resize", () => {
  lastPointerX = window.innerWidth / 2;
  lastPointerY = window.innerHeight / 2;
  moveEyes(lastPointerX, lastPointerY);
});

// Initialize everything when the page loads
document.addEventListener("DOMContentLoaded", () => {
  setupEyelids();
  startRandomBlinking();
  initializeEyeBehavior();
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
