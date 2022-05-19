const projectsContainer = document.querySelector("#projects-container");

const projectItem = ({
  id,
  title,
  description,
  createdOn,
  technologies,
  role,
  live = "",
  github = "",
}) => `<div class="portfolio-item">
<div class="portfolio-item-thumbnail">
  <img src="img/portfolio/${id}.webp" alt="">
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
      <li>View Project - <span><a href="${github}" class="pgithub"></a></span></li>
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
  const live = portfolioItem.querySelector(".pgithub").href;

  document.querySelector(".pp-thumbnail img").src = portfolioItem.querySelector(
    ".portfolio-item-thumbnail img"
  ).src;
  document.querySelector(".pp-header h3").innerHTML = title;
  document.querySelector(".pp-body .description p").innerHTML = description;
  document.querySelector("#created-on").innerHTML = createdOn;
  document.querySelector("#technologies").innerHTML = technologies;
  document.querySelector("#role").innerHTML = role;
  document.querySelector("#github").href = live;
  document.querySelector("#github").innerHTML = "view on github";
}

// function toggleSuccessMessage() {
//   hideActiveSection();
//   document.querySelector(".message-popup").classList.toggle("active");
// }

// const contactForm = document.forms["contact-form"];
// contactForm.addEventListener("submit", (e) => {
//   e.preventDefault();
//   const AIRTABLE_WEBHOOK =
//     "https://hooks.airtable.com/workflows/v1/genericWebhook/appk7UjBHcftYL0zF/wflzI54oVydBWyNfm/wtrOW9pRe3aVTYprv";
//   fetch(AIRTABLE_WEBHOOK, {
//     // Adding method type
//     method: "POST",
//     mode: "no-cors",
//     // Adding body or contents to send
//     body: JSON.stringify({
//       name: e.target["name"].value,
//       email: e.target["name"].value,
//       subject: e.target["subject"].value,
//       message: e.target["message"].value,
//     }),

//     // Adding headers to the request
//     headers: {
//       Accept: "*/*",
//       "Accept-Encoding": "gzip, deflate, br",
//       Connection: "keep-alive",
//       "Content-type": "application/json; charset=UTF-8",
//     },
//   })
//     // Converting to JSON
//     .then(async (response) => {
//       console.log(await response.json());
//     });

//   // Displaying results to console
// });

// const popupOkButton = document.querySelector(
//   ".message-popup .message-inner .button-container button"
// );

// popupOkButton.addEventListener("click", (e) => toggleSuccessMessage());
