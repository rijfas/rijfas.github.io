const projectsContainer = document.querySelector("#projects-container");

const projectItem = ({
  id,
  title,
  description,
  createdOn,
  technologies,
  role,
  live,
}) => `<div class="portfolio-item">
<div class="portfolio-item-thumbnail">
  <img src="img/portfolio/${id}.png" alt="">
</div>
<h3 class="portfolio-item-title ptitle">${title}</h3>
<button type="button" class="btn view-project-button">view project</button>
<div class="portfolio-item-details">
  <div class="description">
    <p class="pdescription">${description}</p>
  </div>
  <div class="general-info">
    <ul>
      <li>Created on - <span class="pcreatedon">${createdOn}</span></li>
      <li>technologies used - <span class="ptechnologies">${technologies}</span></li>
      <li>Role - <span class="prole">${role}</span></li>
      <li>View Live - <span><a href="${live}" class="plive">View on GitHub</a></span></li>
    </ul>
  </div>
</div>
</div>`;

window.addEventListener("load", async () => {
  let projects = await fetch("json/portfolio.json");
  projects = await projects.json();
  projects.forEach((element) => {
    projectsContainer.innerHTML += projectItem(element);
  });

  document.querySelector(".main").classList.remove("hidden");
  document.querySelector(".home-section").classList.add("active");
  document.querySelector(".page-loader").classList.add("fade-out");
  setTimeout(() => {
    document.querySelector(".page-loader").style.display = "none";
  }, 600);
});

const navToggler = document.querySelector(".nav-toggler");
navToggler.addEventListener("click", () => {
  hideActiveSection();
  toggleNavbar();
  document.body.classList.toggle("hide-scroll-bar");
});

function hideActiveSection() {
  document.querySelector("section.active").classList.toggle("fade-out");
}

function toggleNavbar() {
  document.querySelector(".header").classList.toggle("active");
}

document.addEventListener("click", (e) => {
  if (e.target.classList.contains("link-item") && e.target.hash !== "") {
    document.querySelector(".overlay").classList.add("active");
    navToggler.classList.add("hide");
    if (e.target.classList.contains("nav-item")) {
      toggleNavbar();
    } else {
      hideActiveSection();
      document.body.classList.add("hide-scroll-bar");
    }
    setTimeout(() => {
      document
        .querySelector("section.active")
        .classList.remove("active", "fade-out");
      document.querySelector(e.target.hash).classList.add("active");
      window.scrollTo(0, 0);
      document.body.classList.remove("hide-scroll-bar");
      navToggler.classList.remove("hide");
      document.querySelector(".overlay").classList.remove("active");
    }, 500);
  }
});

const tabsContainer = document.querySelector(".about-tabs");
const aboutSection = document.querySelector(".about-section");

tabsContainer.addEventListener("click", (e) => {
  if (
    e.target.classList.contains("tab-item") &&
    !e.target.classList.contains("active")
  ) {
    tabsContainer.querySelector(".active").classList.remove("active");
    e.target.classList.add("active");
    const target = e.target.getAttribute("data-target");
    console.log(target);
    aboutSection
      .querySelector(".tab-content.active")
      .classList.remove("active");
    aboutSection.querySelector(target).classList.add("active");
  }
});

document.addEventListener("click", (e) => {
  if (e.target.classList.contains("view-project-button")) {
    togglePopUp();
    document.querySelector(".portfolio-popup").scrollTo(0, 0);
    showPortfolioDetails(e.target.parentElement);
  }
});

document.addEventListener("click", (e) => {
  if (e.target.classList.contains("pp-inner")) {
    togglePopUp();
  }
});

document.querySelector(".pp-close").addEventListener("click", togglePopUp);

function togglePopUp() {
  document.querySelector(".portfolio-popup").classList.toggle("open");
  document.body.classList.toggle("hide-scroll-bar");
  document.querySelector(".main").classList.toggle("fade-out");
}

function showPortfolioDetails(portfolioItem) {
  const title = portfolioItem.querySelector(".ptitle").innerHTML;
  const description = portfolioItem.querySelector(".pdescription").innerHTML;
  const createdOn = portfolioItem.querySelector(".pcreatedon").innerHTML;
  const technologies = portfolioItem.querySelector(".ptechnologies").innerHTML;
  const role = portfolioItem.querySelector(".prole").innerHTML;
  const live = portfolioItem.querySelector(".plive").href;

  document.querySelector(".pp-thumbnail img").src = portfolioItem.querySelector(
    ".portfolio-item-thumbnail img"
  ).src;
  document.querySelector(".pp-header h3").innerHTML = title;
  document.querySelector(".pp-body .description p").innerHTML = description;
  document.querySelector("#created-on").innerHTML = createdOn;
  document.querySelector("#technologies").innerHTML = technologies;
  document.querySelector("#role").innerHTML = role;
  document.querySelector("#live").href = live;
}
